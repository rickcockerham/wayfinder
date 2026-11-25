require "digest"

module Api
  class BaseController < ApplicationController
    # Resolve credentials before the inherited browser CSRF check runs.
    prepend_before_action :authenticate_api_credentials
    skip_before_action :verify_authenticity_token, if: :bearer_authenticated?
    after_action :private_response
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActionController::InvalidAuthenticityToken, with: :invalid_csrf
    rescue_from ActionDispatch::Http::Parameters::ParseError, with: :invalid_json

    private

    # --------------------------------------------------------------------------
    def authenticate_api_credentials
      # Keep authentication failures as private as successful API responses.
      response.headers["Cache-Control"] = "no-store"
      authorization = request.headers["Authorization"]
      if authorization.nil?
        # Resolve signed sessions early so CSRF failures still identify their owner.
        data = SimpleAuth.cookie_data(cookies)
        @api_user = User.find_by(id: data[:user_id], access_key: data[:access_key]) if data
        request.env["wayfinder.api_authentication_method"] = "session" if data
        request.env["wayfinder.api_user_id"] = @api_user.id if @api_user
        return
      end

      # Accept one explicit bearer credential; malformed headers cannot use cookies.
      request.env["wayfinder.api_authentication_method"] = "bearer"
      token = authorization.match(/\ABearer ([^\s,]+)\z/i)&.captures&.first
      expected_digest = ENV["WAYFINDER_API_TOKEN_SHA256"].to_s
      user_id = ENV["WAYFINDER_API_USER_ID"].to_s
      configured = expected_digest.match?(/\A[0-9a-f]{64}\z/) && user_id.match?(/\A[1-9]\d*\z/)

      # Compare fixed-size digests and resolve the configured owner on each request.
      if token && configured && ActiveSupport::SecurityUtils.fixed_length_secure_compare(Digest::SHA256.hexdigest(token), expected_digest)
        @api_user = User.find_by(id: user_id)
      end
      @api_bearer_authenticated = @api_user.present?
      request.env["wayfinder.api_user_id"] = @api_user.id if bearer_authenticated?
      render json: { error: "unauthorized" }, status: :unauthorized unless bearer_authenticated?
    end

    # --------------------------------------------------------------------------
    def bearer_authenticated?
      # Only a verified credential and existing owner can bypass browser CSRF.
      @api_bearer_authenticated == true
    end

    # --------------------------------------------------------------------------
    def require_authentication
      # The prepended credential check never provisions users or changes ownership.
      render json: { error: "unauthorized" }, status: :unauthorized unless @api_user
    end

    # --------------------------------------------------------------------------
    def set_current_user
      Current.user = @api_user
    end

    # --------------------------------------------------------------------------
    def private_response
      response.headers["Cache-Control"] = "no-store"
      # Bearer clients do not need a browser session or a CSRF token.
      response.headers["X-CSRF-Token"] = form_authenticity_token if @api_user && !bearer_authenticated?
    end

    # --------------------------------------------------------------------------
    def not_found
      render json: { error: "not_found" }, status: :not_found
    end

    # --------------------------------------------------------------------------
    def invalid_csrf
      render json: { error: "invalid_csrf_token" }, status: :unprocessable_entity
    end

    # --------------------------------------------------------------------------
    def invalid_json
      render json: { error: "invalid_json" }, status: :bad_request
    end
  end
end
