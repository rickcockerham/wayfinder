module Api
  class InventoryBaseController < BaseController
    rescue_from ActiveRecord::RecordInvalid, with: :invalid_record
    rescue_from ActiveRecord::RecordNotUnique, with: :conflict

    private

    # --------------------------------------------------------------------------
    def invalid_record(error)
      render json: { error: "validation_failed", details: error.record.errors.to_hash }, status: :unprocessable_entity
    end

    # --------------------------------------------------------------------------
    def conflict
      render json: { error: "conflict", details: "Resolve by ID; no records were merged" }, status: :conflict
    end

    # --------------------------------------------------------------------------
    def json_input(key, fields)
      unless request.media_type == "application/json"
        render json: { error: "json_required" }, status: :unsupported_media_type
        return
      end
      input = params[key]
      unless input.is_a?(ActionController::Parameters) && input.present?
        render json: { error: "object_required" }, status: :bad_request
        return
      end
      unless (input.keys - fields).empty?
        render json: { error: "unknown_fields" }, status: :unprocessable_entity
        return
      end
      input
    end

    # --------------------------------------------------------------------------
    def page(scope)
      limit = params.fetch(:limit, "50").to_s
      after_id = params.fetch(:after_id, "0").to_s
      unless limit.match?(/\A\d+\z/) && (1..100).cover?(limit.to_i) && after_id.match?(/\A\d+\z/)
        render json: { error: "invalid_pagination" }, status: :bad_request
        return
      end
      rows = scope.where("id > ?", after_id.to_i).order(:id).limit(limit.to_i + 1).to_a
      [rows.first(limit.to_i), rows.size > limit.to_i ? rows[limit.to_i - 1].id : nil]
    end

    # --------------------------------------------------------------------------
    def location_json(location)
      location.attributes.slice("id", "name", "parent_id", "hidden").merge("path" => location.path)
    end

    # --------------------------------------------------------------------------
    def valid_id?(value)
      value.is_a?(Integer) && (1..9_223_372_036_854_775_807).cover?(value)
    end
  end
end
