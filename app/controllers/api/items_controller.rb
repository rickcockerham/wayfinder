require "digest"

module Api
  class ItemsController < ApplicationController
    include FilterPersistence
    FIELDS = %w[title notes category_id mood_id parent_id personal_impact emotional_impact family_impact time_scale deadline hide_days done recurrence_kind recurrence_unit recurrence_interval recurrence_day_of_month recurrence_month_of_year].freeze
    INTEGERS = %w[category_id mood_id parent_id personal_impact emotional_impact family_impact time_scale hide_days recurrence_interval recurrence_day_of_month recurrence_month_of_year].freeze
    NULLABLE = %w[parent_id recurrence_day_of_month recurrence_month_of_year].freeze

    # Verify explicit credentials before Rails checks browser CSRF tokens.
    prepend_before_action :authenticate_api_credentials
    skip_before_action :verify_authenticity_token, if: :bearer_authenticated?
    before_action :find_item, only: %i[show update destroy]
    after_action :private_response
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActionController::InvalidAuthenticityToken, with: :invalid_csrf
    rescue_from ActionDispatch::Http::Parameters::ParseError, with: :invalid_json

    # --------------------------------------------------------------------------
    def priorities
      # A morning report always uses empty-search eligibility, never search bypasses.
      if params[:q].present?
        return render json: { error: "empty_search_required" }, status: :bad_request
      end
      # Bound response size independently of browser page-size preferences.
      limit = params.fetch(:limit, "5")
      unless limit.is_a?(String) && limit.match?(/\A\d+\z/) && (1..100).cover?(limit.to_i)
        return render json: { error: "invalid_limit" }, status: :bad_request
      end
      limit = limit.to_i
      # Reject malformed filter shapes before invoking the existing home normalizer.
      invalid_shape = %i[category_id time_i sort per].any? { |key| params.key?(key) && !params[key].is_a?(String) }
      invalid_shape ||= Array(params[:mood_ids]).any? { |value| !value.is_a?(String) }
      if invalid_shape
        return render json: { error: "invalid_filters" }, status: :bad_request
      end
      # Fresh home defaults plus explicit overrides; do not read or persist sessions.
      filters = sanity(apply_params(default_filters)).merge(q: "", per: limit)
      items = HomeItemSelection.new(current_user, filters).call.first(limit)
      render json: {
        observed_at: Time.current.utc.iso8601,
        filter_source: "fresh_home_defaults_with_explicit_overrides",
        filters: filters,
        items: items.map { |item| {
          id: item.id, title: item.title, url: item_url(item),
          deadline: item.deadline, hide_days: item.hide_days,
          importance_score: item.importance_score
        } }
      }
    end

    # --------------------------------------------------------------------------
    def index
      limit = params.fetch(:limit, "50").to_s
      after_id = params.fetch(:after_id, "0").to_s
      unless limit.match?(/\A\d+\z/) && (1..100).cover?(limit.to_i) && after_id.match?(/\A\d+\z/)
        return render json: { error: "invalid_pagination" }, status: :bad_request
      end
      rows = current_user.items.where("id > ?", after_id.to_i).order(:id).limit(limit.to_i + 1).to_a
      more = rows.length > limit.to_i
      rows = rows.first(limit.to_i)
      payload = { items: rows.map { |item| item.attributes.slice("id", "title", "category_id", "mood_id", "personal_impact", "emotional_impact", "family_impact", "deadline", "time_scale", "done") }, next_after_id: more ? rows.last.id : nil }
      # Opt-in create metadata mirrors visible web choices without catalog routes.
      if params[:include_choices] == "1"
        payload[:choices] = {
          categories: current_user.categories.visible.order(:name, :id).pluck(:id, :name).map { |id, name| { id: id, name: name } },
          moods: current_user.moods.visible.order(:name, :id).pluck(:id, :name).map { |id, name| { id: id, name: name } }
        }
      end
      render json: payload
    end

    # --------------------------------------------------------------------------
    def show
      render json: { item: item_json(@item) }
    end

    # --------------------------------------------------------------------------
    def create
      attributes = validated_attributes
      return if performed?
      @item = current_user.items.new
      persist_item(attributes, created: true)
    end

    # --------------------------------------------------------------------------
    def update
      attributes = validated_attributes
      return if performed?
      persist_item(attributes, created: false)
    end

    # --------------------------------------------------------------------------
    def destroy
      # Preserve the web's hard delete, dependent destroys and child nullification.
      if @item.destroy
        render json: { deleted: @item.id }
      else
        render json: { error: "deletion_failed", details: @item.errors.to_hash }, status: :unprocessable_entity
      end
    rescue ActiveRecord::InvalidForeignKey
      render json: { error: "item_in_use" }, status: :conflict
    end

    private

    # --------------------------------------------------------------------------
    def importance_setting
      # GET must not create settings when an owner has never saved any.
      @importance_setting ||= current_user.importance_setting ||
        ImportanceSetting.new(ImportanceSetting.default_attributes)
    end


    # --------------------------------------------------------------------------
    def authenticate_api_credentials
      # Keep authentication failures as private as successful API responses.
      response.headers["Cache-Control"] = "no-store"
      authorization = request.headers["Authorization"]
      if authorization.nil?
        # Resolve signed sessions early so CSRF failures still identify their owner.
        data = SimpleAuth.cookie_data(cookies)
        @api_user = User.find_by(id: data[:user_id], access_key: data[:access_key]) if data
        request.env["wayfinder.api_authentication_method"] = "session" if data
        request.env["wayfinder.api_user_id"] = @api_user.id if @api_user
        return
      end

      # Accept one explicit bearer credential; malformed headers cannot use cookies.
      request.env["wayfinder.api_authentication_method"] = "bearer"
      token = authorization.match(/\ABearer ([^\s,]+)\z/i)&.captures&.first
      expected_digest = ENV["WAYFINDER_API_TOKEN_SHA256"].to_s
      user_id = ENV["WAYFINDER_API_USER_ID"].to_s
      configured = expected_digest.match?(/\A[0-9a-f]{64}\z/) && user_id.match?(/\A[1-9]\d*\z/)

      # Compare only fixed-size digests and resolve the configured owner each time.
      if token && configured && ActiveSupport::SecurityUtils.fixed_length_secure_compare(Digest::SHA256.hexdigest(token), expected_digest)
        @api_user = User.find_by(id: user_id)
      end
      @api_bearer_authenticated = @api_user.present?
      request.env["wayfinder.api_user_id"] = @api_user.id if bearer_authenticated?
      render json: { error: "unauthorized" }, status: :unauthorized unless bearer_authenticated?
    end

    # --------------------------------------------------------------------------
    def bearer_authenticated?
      # CSRF exemption applies only after both the credential and owner were verified.
      @api_bearer_authenticated == true
    end

    # --------------------------------------------------------------------------
    def require_authentication
      # The prepended credential check never provisions users or changes ownership.
      render json: { error: "unauthorized" }, status: :unauthorized unless @api_user
    end

    # --------------------------------------------------------------------------
    def set_current_user
      Current.user = @api_user
    end

    # --------------------------------------------------------------------------
    def private_response
      response.headers["Cache-Control"] = "no-store"
      # Bearer clients do not need a browser session or a CSRF token.
      response.headers["X-CSRF-Token"] = form_authenticity_token if @api_user && !bearer_authenticated?
    end

    # --------------------------------------------------------------------------
    def find_item
      @item = current_user.items.find(params[:id])
    end

    # --------------------------------------------------------------------------
    def not_found
      render json: { error: "not_found" }, status: :not_found
    end

    # --------------------------------------------------------------------------
    def invalid_csrf
      render json: { error: "invalid_csrf_token" }, status: :unprocessable_entity
    end

    # --------------------------------------------------------------------------
    def invalid_json
      render json: { error: "invalid_json" }, status: :bad_request
    end

    # --------------------------------------------------------------------------
    def item_json(item)
      item.attributes.slice("id", *FIELDS, "completed_at", "created_at", "updated_at")
        .merge("recurrence_kind" => item.recurrence_kind, "recurrence_unit" => item.recurrence_unit)
    end

    # --------------------------------------------------------------------------
    def validated_attributes
      unless request.media_type == "application/json"
        render json: { error: "json_required" }, status: :unsupported_media_type
        return
      end
      input = params[:item]
      unless input.is_a?(ActionController::Parameters) && input.present?
        render json: { error: "item_object_required" }, status: :bad_request
        return
      end
      errors = {}
      (input.keys - FIELDS).each { |field| errors[field] = ["is not writable"] }
      input.each do |field, value|
        valid = if INTEGERS.include?(field)
                  (value.is_a?(Integer) && (field.end_with?("_id") ? (1..9_223_372_036_854_775_807) : (-2_147_483_648..2_147_483_647)).cover?(value)) || (value.nil? && NULLABLE.include?(field))
                elsif field == "done"
                  value == true || value == false
                elsif field == "deadline"
                  value.nil? || value == "" || (value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/) && (Date.iso8601(value) rescue false))
                elsif field == "recurrence_kind"
                  Item.recurrence_kinds.key?(value)
                elsif field == "recurrence_unit"
                  Item.recurrence_units.key?(value)
                else
                  value.is_a?(String) || (field == "notes" && value.nil?)
                end
        errors[field] = ["has an invalid type or value"] unless valid
        errors[field] = ["is too long (maximum 255 characters)"] if field == "title" && value.is_a?(String) && value.length > 255
        if %w[personal_impact emotional_impact family_impact].include?(field) && value.is_a?(Integer) && !(0..5).cover?(value)
          errors[field] = ["must be between 0 and 5"]
        end
        if field == "time_scale" && value.is_a?(Integer) && !(0..7).cover?(value)
          errors[field] = ["must be between 0 and 7"]
        end
      end
      # Resolve every supplied association within the authenticated user's scope.
      { "category_id" => current_user.categories, "mood_id" => current_user.moods, "parent_id" => current_user.items }.each do |field, scope|
        next unless input.key?(field) && input[field].present? && !errors.key?(field)
        errors[field] = ["is unavailable"] unless scope.exists?(id: input[field])
        errors[field] = ["cannot be the item itself"] if field == "parent_id" && @item && input[field] == @item.id
      end
      if errors.any?
        render json: { error: "validation_failed", details: errors }, status: :unprocessable_entity
        return
      end
      input.permit(*FIELDS).to_h
    end

    # --------------------------------------------------------------------------
    def persist_item(attributes, created:)
      # Keep completion, inventory consumption and recurrence atomic for API callers.
      @item.with_lock do
        was_done = @item.done?
        @item.assign_attributes(attributes)
        @item.save!
        if @item.done? && !was_done
          @item.update!(completed_at: Time.current)
          ItemCompletion.new(@item).consume!
          RecurrenceAdvancer.new(@item).call
        elsif was_done && !@item.done?
          @item.update!(completed_at: nil)
          @item.reactivate_blockers!
        end
      end
      render json: { item: item_json(@item.reload) }, status: created ? :created : :ok
    rescue ActiveRecord::RecordInvalid => error
      render json: { error: "validation_failed", details: error.record.errors.to_hash }, status: :unprocessable_entity
    rescue ActiveRecord::InvalidForeignKey
      render json: { error: "association_unavailable" }, status: :unprocessable_entity
    rescue StandardError => error
      Rails.logger.error("Item API mutation failed: #{error.class}")
      render json: { error: "mutation_failed" }, status: :internal_server_error
    end
  end
end
