# app/controllers/inventory_items_controller.rb
class InventoryItemsController < ApplicationController
  before_action :set_inventory_item, only: %i[show edit update destroy]

  def index
    @inventory_items = InventoryItem.includes(:location).order(:name)
    if !params[:zeros]
      @inventory_items = @inventory_items.where("qty_have > 0")
    end
  end

  def show; end

  def new
    @inventory_item = InventoryItem.new
  end

  def edit; end

  def create
    @inventory_item = InventoryItem.new(inventory_item_params)
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
    @inventory_item = InventoryItem.find(params[:id])
  end

  def inventory_item_params
    params.require(:inventory_item).permit(:name, :qty_have, :unit, :location_id, :shop_id)
  end
end
