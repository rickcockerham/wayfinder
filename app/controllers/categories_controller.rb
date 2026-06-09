# app/controllers/categories_controller.rb
class CategoriesController < ApplicationController
  before_action :set_category, only: %i[show edit update destroy]

  def index
    @categories = Category.for_user(current_user).order(:name)
  end
  def show; end
  def new; @category = current_user.categories.new; end
  def edit; end

  def create
    @category = current_user.categories.new(category_params)
    if @category.save
      redirect_to categories_path, notice: "Category created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @category.update(category_params)
      redirect_to categories_path, notice: "Category updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @category.destroy
    redirect_to categories_url, notice: "Category deleted."
  end

  private
  def set_category; @category = Category.for_user(current_user).find(params[:id]); end
  def category_params; params.require(:category).permit(:name); end
end
