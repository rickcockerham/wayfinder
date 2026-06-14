# app/controllers/locations_controller.rb
class LocationsController < ApplicationController
  before_action :set_location, only: %i[show edit update destroy]

  def index
    @locations = Location.for_user(current_user).order(:name)
  end
  def show; end
  def new; @location = current_user.locations.new; end
  def edit; end

  def create
    @location = current_user.locations.new(location_params)
    if @location.save
      redirect_to locations_path, notice: "Location created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @location.update(location_params)
      redirect_to locations_path, notice: "Location updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @location.destroy
    redirect_to locations_url, notice: "Location deleted."
  end

  private
  def set_location; @location = Location.for_user(current_user).find(params[:id]); end
  def location_params; params.require(:location).permit(:name, :hidden); end
end
