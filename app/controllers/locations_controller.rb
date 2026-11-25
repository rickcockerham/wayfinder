# app/controllers/locations_controller.rb
class LocationsController < ApplicationController
  before_action :set_location, only: %i[show edit update destroy]

  #-----------------------------------------------------------------------------
  def index
    # Keep each branch together while displaying its complete storage path.
    @locations = current_user.locations.includes(:parent).sort_by { |location| location.full_name.downcase }
  end

  #-----------------------------------------------------------------------------
  def show
    # Browse one level at a time without imposing a fixed storage taxonomy or depth.
    @children = current_user.locations.where(parent_id: @location.id).order(:name)
  end

  #-----------------------------------------------------------------------------
  def new
    # An Add sub-location link selects an owned parent before rendering the form.
    @location = current_user.locations.new(parent: owned_parent(params[:parent_id]))
    load_parent_locations
  end

  #-----------------------------------------------------------------------------
  def edit
    load_parent_locations
  end

  #-----------------------------------------------------------------------------
  def create
    @location = current_user.locations.new(location_params)
    if @location.save
      redirect_to locations_path, notice: "Location created."
    else
      load_parent_locations
      render :new, status: :unprocessable_entity
    end
  end

  #-----------------------------------------------------------------------------
  def update
    # Existing ancestry stays immutable; the model explicitly rejects attempted moves.
    if @location.update(location_params)
      redirect_to locations_path, notice: "Location updated."
    else
      load_parent_locations
      render :edit, status: :unprocessable_entity
    end
  end

  #-----------------------------------------------------------------------------
  def destroy
    @location.destroy!
    redirect_to locations_url, notice: "Location deleted."
  rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::InvalidForeignKey
    # A populated branch must remain intact and report why deletion was refused.
    redirect_to location_path(@location), alert: "This location contains sub-locations or inventory and cannot be deleted."
  end

  private

  #-----------------------------------------------------------------------------
  def set_location
    @location = current_user.locations.find(params[:id])
  end

  #-----------------------------------------------------------------------------
  def location_params
    attributes = params.require(:location).permit(:name, :hidden, :parent_id)
    # Resolve form IDs within the owner scope before assigning the association.
    attributes[:parent] = owned_parent(attributes.delete(:parent_id)) if attributes.key?(:parent_id)
    attributes
  end

  #-----------------------------------------------------------------------------
  def owned_parent(id)
    return if id.nil? || id == ""

    # Reject malformed or inaccessible IDs without revealing another owner's names.
    raise ActiveRecord::RecordNotFound unless id.is_a?(String) && id.match?(/\A[1-9]\d*\z/)
    current_user.locations.find(id)
  end

  #-----------------------------------------------------------------------------
  def load_parent_locations
    # Include an explicitly selected hidden parent, as existing reference forms do.
    @parent_locations = visible_records(current_user.locations, current_id: @location.parent_id)
      .sort_by { |location| location.full_name.downcase }
  end
end
