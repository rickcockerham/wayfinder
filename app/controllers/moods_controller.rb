# app/controllers/moods_controller.rb
class MoodsController < ApplicationController
  before_action :set_mood, only: %i[show edit update destroy]

  def index
    @moods = Mood.for_user(current_user).order(:name)
  end
  def show; end
  def new; @mood = current_user.moods.new; end
  def edit; end

  def create
    @mood = current_user.moods.new(mood_params)
    if @mood.save
      redirect_to moods_path, notice: "Mood created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @mood.update(mood_params)
      redirect_to moods_path, notice: "Mood updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @mood.destroy
    redirect_to moods_url, notice: "Mood deleted."
  end

  private
  def set_mood; @mood = Mood.for_user(current_user).find(params[:id]); end
  def mood_params; params.require(:mood).permit(:name); end
end
