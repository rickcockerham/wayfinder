# app/controllers/material_requirements_controller.rb
class MaterialRequirementsController < ApplicationController
  before_action :set_material_requirement, only: %i[show edit update destroy]
  before_action :load_form_collections, only: %i[new edit create update]

  def index
    @material_requirements = MaterialRequirement.for_user(current_user).includes(:item, :shop).order(created_at: :desc)
  end

  def show; end

  def new
    @material_requirement = current_user.material_requirements.new(item_id: owned_item_id(params[:item_id]))
  end

  def edit; end

  def create
    @material_requirement = current_user.material_requirements.new(material_requirement_params)
    if @material_requirement.save
      redirect_to material_requirements_path, notice: "Material requirement created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @material_requirement.update(material_requirement_params)
      redirect_to (@item ? @item : shopping_path), notice: "Material requirement updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @item = @material_requirement.item
    @material_requirement.destroy

    respond_to do |format|
      format.turbo_stream # renders destroy.turbo_stream.erb
      format.html { redirect_back fallback_location: @item, notice: "Material removed." }
    end
  end

  private
  def set_material_requirement
    @material_requirement = MaterialRequirement.for_user(current_user).find(params[:id])
    @item = @material_requirement.item rescue nil
  end

  def material_requirement_params
    params.require(:material_requirement).permit(:item_id, :name, :qty_needed, :unit, :shop_id)
  end

  def load_form_collections
    @items = Item.for_user(current_user).order(:title).to_a
    @shops = visible_records(Shop.for_user(current_user), current_id: @material_requirement&.shop_id)
  end

  def owned_item_id(id)
    Item.for_user(current_user).find_by(id: id)&.id
  end
end
