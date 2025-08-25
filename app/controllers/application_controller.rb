  # app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :require_authentication

  private

  def require_authentication
    return unless SimpleAuth.enabled?

    # Auto-login via ?key=... (clean the URL immediately to avoid leaking in referers)
    if params[:key].present?
      if SimpleAuth.valid_key?(params[:key])
        SimpleAuth.set_cookie!(cookies)
        # Redirect to same path without the key param
        return redirect_to url_for(params.permit!.to_h.except(:key))
      else
        SimpleAuth.clear_cookie!(cookies)
        return redirect_to(login_path, alert: "Invalid key.")
      end
    end

    return if SimpleAuth.cookie_ok?(cookies)
    redirect_to login_path, alert: "Please sign in."
  end
end
