module Api
  class ItemsController < ApplicationController
    FIELDS = %w[title notes category_id mood_id parent_id personal_impact emotional_impact family_impact time_scale deadline hide_days done recurrence_kind recurrence_unit recurrence_interval recurrence_day_of_month recurrence_month_of_year].freeze
    INTEGERS = %w[category_id mood_id parent_id personal_impact emotional_impact family_impact time_scale hide_days recurrence_interval recurrence_day_of_month recurrence_month_of_year].freeze
    NULLABLE = %w[parent_id recurrence_day_of_month recurrence_month_of_year].freeze

    before_action :find_item, only: %i[show update destroy]
    after_action :private_response
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActionController::InvalidAuthenticityToken, with: :invalid_csrf
    rescue_from ActionDispatch::Http::Parameters::ParseError, with: :invalid_json

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
    def require_authentication
      # Use existing signed cookies, but never provision a legacy default user.
      data = SimpleAuth.cookie_data(cookies)
      @api_user = User.find_by(id: data[:user_id], access_key: data[:access_key]) if data
      render json: { error: "unauthorized" }, status: :unauthorized unless @api_user
    end

    # --------------------------------------------------------------------------
    def set_current_user
      Current.user = @api_user
    end

    # --------------------------------------------------------------------------
    def private_response
      response.headers["Cache-Control"] = "no-store"
      response.headers["X-CSRF-Token"] = form_authenticity_token if @api_user
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
