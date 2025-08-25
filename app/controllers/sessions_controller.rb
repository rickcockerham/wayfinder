# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create]

  def new; end

  def create
    key = params[:key].to_s
    if SimpleAuth.valid_key?(key)
      SimpleAuth.set_cookie!(cookies)
      redirect_to(root_path, notice: "Signed in.")
    else
      flash.now[:alert] = "Invalid key."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    SimpleAuth.clear_cookie!(cookies)
    redirect_to login_path, notice: "Signed out."
  end
end
