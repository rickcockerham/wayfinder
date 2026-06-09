# config/initializers/simple_auth.rb
module SimpleAuth
  COOKIE_NAME = :auth_v1

  module_function

  def secret
    Rails.application.credentials.dig(:wayfinder, :access_token) ||
      ENV["WAYFINDER_ACCESS_TOKEN"]
  end

  def enabled?
    User.exists? || secret.present?
  end

  def valid_key?(key)
    return false unless key.present?

    return true if User.exists?(access_key: key)
    return false unless secret.present?
    ActiveSupport::SecurityUtils.secure_compare(key.to_s, secret.to_s)
  end

  def user_for_key(key)
    return nil unless key.present?
    User.find_by(access_key: key) || ensure_default_user(key)
  end

  def current_key(cookies)
    data = cookie_data(cookies)
    return unless data

    data[:access_key]
  end

  def set_cookie!(cookies, user)
    cookies.permanent.signed[COOKIE_NAME] = {
      value: { user_id: user.id, access_key: user.access_key },
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }
  end

  def clear_cookie!(cookies)
    cookies.delete(COOKIE_NAME)
  end

  def cookie_ok?(cookies)
    current_user(cookies).present?
  end

  def current_user(cookies)
    data = cookie_data(cookies)
    return unless data

    user = User.find_by(id: data[:user_id], access_key: data[:access_key])
    return user if user.present?

    return unless secret.present?
    return unless ActiveSupport::SecurityUtils.secure_compare(data[:access_key].to_s, secret.to_s)

    ensure_default_user(data[:access_key])
  end

  def cookie_data(cookies)
    data = cookies.signed[COOKIE_NAME]
    return unless data.is_a?(Hash)

    data.with_indifferent_access
  end

  def ensure_default_user(key)
    User.find_or_create_by!(access_key: key) do |user|
      user.name = "Default"
    end
  end
end
