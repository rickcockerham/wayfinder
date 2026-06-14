# coding: utf-8
# app/controllers/shopping_controller.rb
class ShoppingController < ApplicationController
  def index
    @shops     = Shop.for_user(current_user).visible.order(:name).to_a
    @locations = Location.for_user(current_user).visible.order(:name).to_a

    requested_shop_id = params[:shop_id].presence&.to_i
    @shop_id = @shops.any? { |shop| shop.id == requested_shop_id } ? requested_shop_id : @shops.first&.id

    requested_location_id = params[:location_id].presence&.to_i
    @location_id = @locations.any? { |location| location.id == requested_location_id } ? requested_location_id : nil

    @requirements = if @shop_id.present?
      MaterialRequirement
        .for_user(current_user)
        .includes(:item, :shop)
        .joins(:item)
        .merge(Item.for_user(current_user))
        .where(shop_id: @shop_id)
        .order("items.title ASC, material_requirements.name ASC")
    else
      MaterialRequirement.none
    end

    @reqs_by_item = @requirements.group_by(&:item)
  end

  def purchase
    shop_id     = params[:shop_id].presence&.to_i
    location_id = params[:location_id].presence&.to_i
    ids         = Array(params[:purchase_ids]).map(&:to_i).uniq
    shop        = Shop.for_user(current_user).find_by(id: shop_id)
    location    = Location.for_user(current_user).find_by(id: location_id)

    count = 0
    MaterialRequirement.for_user(current_user).where(id: ids).includes(:item, :shop).find_each do |mr|
      # 1) Find or create inventory row (by name + optional location)
      rel = InventoryItem.for_user(current_user).where("LOWER(name)=?", mr.name.downcase)
      #rel = location_id ? rel.where(location_id:) : rel.where(location_id: nil)
      inv = rel.first

      if inv
        inv.update!(qty_have: inv.qty_have.to_f + mr.qty_needed.to_f, shop: shop || mr.shop)
      else
        inv = InventoryItem.create!(
          user: current_user,
          name: mr.name,
          qty_have: mr.qty_needed,
          unit: mr.unit.to_s,
          location: location,
          shop: shop || mr.shop
        )
      end

      # 2) Attach to original Item (reserve/associate what was bought)
      ii = ItemInventory.for_user(current_user).find_or_initialize_by(item: mr.item, inventory_item: inv)
      ii.user = current_user
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
