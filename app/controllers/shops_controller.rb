# app/controllers/shops_controller.rb
class ShopsController < ApplicationController
  before_action :set_shop, only: %i[show edit update destroy]

  def index
    @shops = Shop.order(:name)
  end
  def show; end
  def new; @shop = Shop.new; end
  def edit; end

  def create
    @shop = Shop.new(shop_params)
    if @shop.save
      redirect_to shops_path, notice: "Shop created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @shop.update(shop_params)
      redirect_to shops_path, notice: "Shop updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @shop.destroy
    redirect_to shops_url, notice: "Shop deleted."
  end

  private
  def set_shop; @shop = Shop.find(params[:id]); end
  def shop_params; params.require(:shop).permit(:name); end
end
