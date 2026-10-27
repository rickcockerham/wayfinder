# app/controllers/inventory_items_controller.rb
class InventoryItemsController < ApplicationController
  before_action :set_inventory_item, only: %i[show edit update destroy]
  before_action :load_form_collections, only: %i[new edit create update]

  # -----------------------------------------------------------------------------
  def index
    @inventory_items = InventoryItem.for_user(current_user).includes(:location).order(:name)
    if !params[:zeros]
      @inventory_items = @inventory_items.where("qty_have > 0 OR qty_have IS NULL")
    end
  end

  def show; end

  def new
    @inventory_item = current_user.inventory_items.new
  end

  def edit; end

  def create
    @inventory_item = current_user.inventory_items.new(inventory_item_params)
    if @inventory_item.save
      redirect_to inventory_items_path, notice: "Inventory item created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @inventory_item.update(inventory_item_params)
      redirect_to inventory_items_path, notice: "Inventory item updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @inventory_item.destroy
    redirect_to inventory_items_url, notice: "Inventory item deleted."
  end

  private
  def set_inventory_item
    @inventory_item = InventoryItem.for_user(current_user).find(params[:id])
  end

  # -----------------------------------------------------------------------------
  def inventory_item_params
    input = params.require(:inventory_item)
    attributes = input.permit(:name, :qty_have, :unit, :location_id, :shop_id)
    # A blank form field preserves the count; only the explicit checkbox clears it.
    attributes.delete(:qty_have) if attributes[:qty_have].blank?
    attributes[:qty_have] = nil if input[:quantity_unknown] == "1"
    attributes
  end

  def load_form_collections
    @locations = visible_records(Location.for_user(current_user), current_id: @inventory_item&.location_id)
    @shops = visible_records(Shop.for_user(current_user), current_id: @inventory_item&.shop_id)
  end
end
