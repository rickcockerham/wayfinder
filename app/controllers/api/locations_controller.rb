module Api
  class LocationsController < InventoryBaseController
    # -----------------------------------------------------------------------------
    def index
      scope = current_user.locations
      scope = scope.where(name: params[:name]) if params[:name].present?
      if params.key?(:parent_id)
        parent = params[:parent_id].present? ? current_user.locations.find(params[:parent_id]) : nil
        scope = scope.where(parent_id: parent&.id)
      end
      result = page(scope)
      return if performed?
      rows, cursor = result
      render json: { locations: rows.map { |row| location_json(row) }, next_after_id: cursor }
    end

    # -----------------------------------------------------------------------------
    def show
      location = current_user.locations.find(params[:id])
      render json: { location: location_json(location) }
    end

    # -----------------------------------------------------------------------------
    def create
      input = json_input(:location, %w[root_id path])
      return if performed?
      segments = input[:path]
      unless segments.is_a?(Array) && segments.present? && segments.all? { |name| name.is_a?(String) && name.present? && name.length <= 255 && name == name.strip } &&
          (!input.key?(:root_id) || valid_id?(input[:root_id]))
        return render json: { error: "invalid_path" }, status: :unprocessable_entity
      end
      created_ids = []
      location = nil
      # Lock the owner, including for the root case, to serialize retries and creation.
      current_user.with_lock do
        location = current_user.locations.find(input[:root_id]) if input.key?(:root_id)
        segments.each do |name|
          matches = current_user.locations.where(parent_id: location&.id, name: name).limit(2).to_a
          raise ActiveRecord::RecordNotUnique if matches.size > 1
          location = matches.first || current_user.locations.create!(name: name, parent: location)
          created_ids << location.id if location.previously_new_record?
        end
      end
      render json: { location: location_json(location), created_ids: created_ids }, status: created_ids.any? ? :created : :ok
    end
  end
end
