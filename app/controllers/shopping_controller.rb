# coding: utf-8
# app/controllers/shopping_controller.rb
class ShoppingController < ApplicationController
  def index
    @shops     = Shop.order(:name).to_a
    @locations = Location.order(:name).to_a

    @shop_id     = (params[:shop_id].presence&.to_i || @shops.first&.id)
    @location_id = params[:location_id].presence&.to_i

    @requirements = MaterialRequirement
      .includes(:item, :shop)
      .joins(:item)
      .where(shop_id: @shop_id)
      .order("items.title ASC, material_requirements.name ASC")

    @reqs_by_item = @requirements.group_by(&:item)
  end

  def purchase
    shop_id     = params[:shop_id].presence&.to_i
    location_id = params[:location_id].presence&.to_i
    ids         = Array(params[:purchase_ids]).map(&:to_i).uniq

    count = 0
    MaterialRequirement.where(id: ids).includes(:item).find_each do |mr|
      # 1) Find or create inventory row (by name + optional location)
      rel = InventoryItem.where("LOWER(name)=?", mr.name.downcase)
      #rel = location_id ? rel.where(location_id:) : rel.where(location_id: nil)
      inv = rel.first

      if inv
        inv.update!(qty_have: inv.qty_have.to_f + mr.qty_needed.to_f, shop_id: shop_id)
      else
        inv = InventoryItem.create!(
          name: mr.name,
          qty_have: mr.qty_needed,
          unit: mr.unit.to_s,
          location_id: location_id,
          shop_id: mr.shop_id
        )
      end

      # 2) Attach to original Item (reserve/associate what was bought)
      ii = ItemInventory.find_or_initialize_by(item_id: mr.item_id, inventory_item_id: inv.id)
      ii.unit = ii.unit.presence || mr.unit.to_s
      ii.qty_reserved = ii.qty_reserved.to_f + mr.qty_needed.to_f
      ii.save!

      # 3) Remove the requirement line (it’s been purchased)
      mr.destroy!
      count += 1
    end

    redirect_to shopping_path(shop_id:, location_id:),
      notice: "#{count} material#{'s' if count != 1} moved to inventory and attached to their items."
  end
end
