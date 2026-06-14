# app/controllers/item_blocks_controller.rb
class ItemBlocksController < ApplicationController
  before_action :set_item_block, only: %i[show edit update destroy]
  before_action :load_items, only: %i[new edit create update]

  def index
    @item_blocks = ItemBlock.for_user(current_user).includes(:blocker, :blocked)
  end

  def show; end

  def new
    @item_block = current_user.item_blocks.new(
      blocked_id: owned_item_id(params[:blocked_id]),
      blocker_id: owned_item_id(params[:blocker_id])
    )
  end

  def edit; end

  def create
    @item_block = current_user.item_blocks.new(item_block_params)
    if @item_block.save
      redirect_to item_blocks_path, notice: "Blocker edge created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @item_block.update(item_block_params)
      redirect_to item_blocks_path, notice: "Blocker edge updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @item_block.destroy
    redirect_to item_blocks_url, notice: "Blocker edge deleted."
  end

  private
  def set_item_block
    @item_block = ItemBlock.for_user(current_user).find(params[:id])
  end

  def item_block_params
    params.require(:item_block).permit(:blocker_id, :blocked_id)
  end

  def load_items
    @items = Item.for_user(current_user).order(:title).to_a
  end

  def owned_item_id(id)
    Item.for_user(current_user).find_by(id: id)&.id
  end
end
