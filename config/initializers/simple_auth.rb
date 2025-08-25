# config/initializers/simple_auth.rb
module SimpleAuth
  COOKIE_NAME = :auth_v1

  module_function

  def secret
    Rails.application.credentials.dig(:wayfinder, :access_token) ||
      ENV["WAYFINDER_ACCESS_TOKEN"]
  end

  def enabled?
    secret.present?
  end

  def valid_key?(key)
    return false unless enabled? && key.present?
    # constant-time compare
    ActiveSupport::SecurityUtils.secure_compare(key.to_s, secret.to_s)
  end

  def set_cookie!(cookies)
    cookies.permanent.signed[COOKIE_NAME] = {
      value: "ok",
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }
  end

  def clear_cookie!(cookies)
    cookies.delete(COOKIE_NAME)
  end

  def cookie_ok?(cookies)
    cookies.signed[COOKIE_NAME] == "ok"
  end
end
