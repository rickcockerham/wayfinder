module Api
  class InventoryItemsController < InventoryBaseController
    # -----------------------------------------------------------------------------
    def index
      scope = current_user.inventory_items.includes(:location)
      if params[:q].present?
        query = "%#{InventoryItem.sanitize_sql_like(params[:q].to_s)}%"
        scope = scope.where("name LIKE :query OR aliases LIKE :query", query: query)
      end
      scope = scope.where(name: params[:name]) if params[:name].present?
      if params.key?(:location_id)
        location = params[:location_id].present? ? current_user.locations.find(params[:location_id]) : nil
        scope = scope.where(location_id: location&.id)
      end
      result = page(scope)
      return if performed?
      rows, cursor = result
      payload = { inventory_items: rows.map { |row| inventory_json(row) }, next_after_id: cursor }
      if params[:include_choices] == "1"
        payload[:shops] = current_user.shops.visible.order(:name, :id).pluck(:id, :name).map { |id, name| { id: id, name: name } }
      end
      render json: payload
    end

    # -----------------------------------------------------------------------------
    def show
      render json: { inventory_item: inventory_json(current_user.inventory_items.find(params[:id])) }
    end

    # -----------------------------------------------------------------------------
    def set_count
      input = json_input(:inventory_item, %w[id name aliases location_id shop_id unit qty_have expected_qty_have])
      return if performed?
      # Decimal strings avoid float rounding and silent database truncation.
      unless input[:name].is_a?(String) && input[:name].present? && input[:name].length <= 255 && input[:name] == input[:name].strip &&
          input[:unit].is_a?(String) && input[:unit].length <= 255 && valid_id?(input[:shop_id]) &&
          input.key?(:location_id) && (input[:location_id].nil? || valid_id?(input[:location_id])) &&
          (!input.key?(:id) || valid_id?(input[:id])) &&
          (!input.key?(:aliases) || (input[:aliases].is_a?(Array) && input[:aliases].all? { |name| name.is_a?(String) && name.present? && name.length <= 255 && name == name.strip })) &&
          decimal_count?(input[:qty_have]) &&
          (!input.key?(:expected_qty_have) || decimal_count?(input[:expected_qty_have]))
        return render json: { error: "validation_failed" }, status: :unprocessable_entity
      end
      row = nil
      created = false
      current_user.with_lock do
        shop = current_user.shops.find(input[:shop_id])
        location = current_user.locations.find(input[:location_id]) if input[:location_id]
        matches = current_user.inventory_items.where(name: input[:name], location_id: location&.id).limit(2).to_a
        if input.key?(:id)
          row = current_user.inventory_items.find(input[:id])
          # An explicit ID disambiguates legacy unlocated duplicates, never moves stock.
          return conflict unless current_user.inventory_items.where(name: input[:name], location_id: location&.id, id: row.id).exists?
        else
          return conflict if matches.size > 1
          row = matches.first
        end
        created = row.nil?
        row ||= current_user.inventory_items.new(name: input[:name], location: location, shop: shop, unit: input[:unit])
        row.with_lock do
          return conflict unless row.shop_id == shop.id && row.unit == input[:unit]
          # A repeated desired count is a no-op. Changes require the last observed count.
          unless created || row.qty_have == BigDecimal(input[:qty_have]) ||
              (input.key?(:expected_qty_have) && row.qty_have == BigDecimal(input[:expected_qty_have]))
            return render json: { error: "stale_count", inventory_item: inventory_json(row) }, status: :conflict
          end
          attributes = { qty_have: input[:qty_have] }
          attributes[:aliases] = input[:aliases].uniq if input.key?(:aliases)
          row.update!(attributes) if created || row.qty_have != BigDecimal(input[:qty_have]) || attributes.key?(:aliases)
        end
      end
      render json: { inventory_item: inventory_json(row), quantity_operation: "set" }, status: created ? :created : :ok
    end

    private

    # -----------------------------------------------------------------------------
    def decimal_count?(value)
      value.is_a?(String) && value.match?(/\A(?:0|[1-9]\d{0,7})(?:\.\d{1,2})?\z/)
    end

    # -----------------------------------------------------------------------------
    def inventory_json(row)
      row.attributes.slice("id", "name", "unit", "shop_id", "location_id").merge(
        "aliases" => row.aliases, "qty_have" => row.qty_have.to_s("F"), "location" => row.location && location_json(row.location))
    end
  end
end
