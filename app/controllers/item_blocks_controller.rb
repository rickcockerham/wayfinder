# app/controllers/item_blocks_controller.rb
class ItemBlocksController < ApplicationController
  before_action :set_item_block, only: %i[show edit update destroy]

  def index
    @item_blocks = ItemBlock.includes(:blocker, :blocked).order(created_at: :desc)
  end

  def show; end

  def new
    @item_block = ItemBlock.new(blocked_id: params[:blocked_id], blocker_id: params[:blocker_id])
  end

  def edit; end

  def create
    @item_block = ItemBlock.new(item_block_params)
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
    @item_block = ItemBlock.find(params[:id])
  end

  def item_block_params
    params.require(:item_block).permit(:blocker_id, :blocked_id)
  end
end
