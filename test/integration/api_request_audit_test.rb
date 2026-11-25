require "test_helper"
require "minitest/mock"
require "digest"
require "stringio"

class ApiRequestAuditTest < ActionDispatch::IntegrationTest
  # ----------------------------------------------------------------------------
  setup do
    # Credentials are deterministic fixtures and never use the real local token.
    @saved_environment = %w[WAYFINDER_API_TOKEN_SHA256 WAYFINDER_API_USER_ID].to_h { |key| [key, ENV[key]] }
    @saved_forgery_protection = ActionController::Base.allow_forgery_protection
    @user = users(:default_user)
    @item = items(:one)
    @token = "wayfinder-audit-test-only-#{'4c' * 24}"
    @authorization = { "Authorization" => "Bearer #{@token}" }
    ENV["WAYFINDER_API_TOKEN_SHA256"] = Digest::SHA256.hexdigest(@token)
    ENV["WAYFINDER_API_USER_ID"] = @user.id.to_s
  end

  # ----------------------------------------------------------------------------
  teardown do
    # Avoid affecting other tests that exercise cookie authentication and CSRF.
    @saved_environment&.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    ActionController::Base.allow_forgery_protection = @saved_forgery_protection
  end

  # ----------------------------------------------------------------------------
  test "bearer requests record UTC timing identity forwarded IP and safe metadata" do
    headers = @authorization.merge(
      "REMOTE_ADDR" => "127.0.0.1",
      "X-Forwarded-For" => "203.0.113.42",
      "X-Request-Id" => "wayfinder-audit-fixture-read",
      "User-Agent" => "Wayfinder audit test"
    )
    before_request = Time.now.utc
    assert_difference("ApiRequestLog.count", 1) do
      get "/api/items", params: { include_choices: 1, ignored_secret: @token }, headers: headers
      assert_response :success
    end
    row = ApiRequestLog.order(:id).last
    # Rails presents this attribute in the application's Central display zone.
    # Verify both its instant and the UTC value actually persisted by MySQL.
    assert_equal :utc, ActiveRecord.default_timezone
    stored_timestamp = ApiRequestLog.where(id: row.id).pick(Arel.sql("DATE_FORMAT(requested_at, '%Y-%m-%d %H:%i:%s.%f')"))
    assert_equal row.requested_at.utc.strftime("%Y-%m-%d %H:%M:%S.%6N"), stored_timestamp
    assert_operator row.requested_at, :>=, before_request - 0.001
    assert_operator row.requested_at, :<=, Time.now.utc
    assert_equal ["203.0.113.42", "127.0.0.1"], [row.remote_ip, row.peer_ip]
    assert_equal ["wayfinder-audit-fixture-read", "GET", "/api/items", 200], row.attributes.values_at("request_id", "http_method", "path", "status")
    assert_operator row.duration_ms, :>=, 0
    assert_equal "Wayfinder audit test", row.user_agent
    assert_equal [@user.id, "bearer", Digest::SHA256.hexdigest(@token)], [row.user_id, row.authentication_method, row.token_fingerprint]
    assert_nil row.exception_class
    assert_not_includes row.attributes.to_json, @token
    assert_not_includes row.attributes.to_json, "ignored_secret"

    # A successful write retains its final status, without recording the body.
    private_title = "Private audit payload must not be retained"
    post "/api/items", params: { item: { title: private_title, category_id: @item.category_id, mood_id: @item.mood_id } }, headers: @authorization, as: :json
    assert_response :created
    row = ApiRequestLog.order(:id).last
    assert_equal ["POST", 201], [row.http_method, row.status]
    assert_not_includes row.attributes.to_json, private_title
    assert_not_includes row.attributes.to_json, @token
    assert_not_includes row.attributes.to_json, @user.access_key
  end

  # ----------------------------------------------------------------------------
  test "anonymous rejected and malformed credentials are recorded without secrets" do
    get "/api/items"
    assert_response :unauthorized
    row = ApiRequestLog.order(:id).last
    assert_equal [401, "anonymous", nil, nil], [row.status, row.authentication_method, row.token_fingerprint, row.user_id]

    # Failed bearer credentials remain correlatable without retaining that token.
    invalid_token = "#{@token}-revoked"
    get "/api/items", headers: { "Authorization" => "Bearer #{invalid_token}" }
    assert_response :unauthorized
    row = ApiRequestLog.order(:id).last
    assert_equal [401, "bearer", Digest::SHA256.hexdigest(invalid_token), nil], [row.status, row.authentication_method, row.token_fingerprint, row.user_id]
    assert_not_includes row.attributes.to_json, invalid_token

    get "/api/items", headers: { "Authorization" => "Bearer #{@token} extra" }
    assert_response :unauthorized
    row = ApiRequestLog.order(:id).last
    assert_equal "bearer", row.authentication_method
    assert_nil row.token_fingerprint
    assert_not_includes row.attributes.to_json, @token
  end

  # ----------------------------------------------------------------------------
  test "routing failures are logged including the bare API prefix" do
    env_config = Rails.application.env_config
    saved_details = env_config["action_dispatch.show_detailed_exceptions"]
    begin
      # DebugExceptions renders detailed local errors without exporting an exception.
      # Production re-raises to ShowExceptions, which supplies the real exception.
      [true, false].each do |detailed|
        env_config["action_dispatch.show_detailed_exceptions"] = detailed
        ["/api/not-a-real-route", "/api"].each do |path|
          assert_difference("ApiRequestLog.count", 1) do
            get path, headers: @authorization
            assert_response :not_found
          end
          row = ApiRequestLog.order(:id).last
          assert_equal [path, 404, "bearer", Digest::SHA256.hexdigest(@token)], [row.path, row.status, row.authentication_method, row.token_fingerprint]
          if detailed
            assert_nil row.exception_class
          else
            assert_equal "ActionController::RoutingError", row.exception_class
          end
          assert_nil row.user_id
        end
      end
    ensure
      env_config["action_dispatch.show_detailed_exceptions"] = saved_details
    end
  end

  # ----------------------------------------------------------------------------
  test "website requests are excluded and cookie API access and CSRF failures are logged" do
    assert_no_difference("ApiRequestLog.count") do
      get login_url
      post login_url, params: { key: @user.access_key }
      assert_redirected_to root_url
      get "/apiary"
      assert_response :not_found
    end

    get "/api/items"
    assert_response :success
    row = ApiRequestLog.order(:id).last
    assert_equal ["session", @user.id, nil], [row.authentication_method, row.user_id, row.token_fingerprint]

    # Failed CSRF must still leave an audit row even if action callbacks are skipped.
    ActionController::Base.allow_forgery_protection = true
    assert_difference("ApiRequestLog.count", 1) do
      patch "/api/items/#{@item.id}", params: { item: { title: "Rejected audit mutation" } }, as: :json
      assert_response :unprocessable_entity
    end
    row = ApiRequestLog.order(:id).last
    assert_equal ["PATCH", 422], [row.http_method, row.status]
    assert_equal ["session", @user.id], [row.authentication_method, row.user_id]
    assert_equal "Default item", @item.reload.title
  end

  # ----------------------------------------------------------------------------
  test "database audit failure leaves the response intact and logs no error details" do
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    failing_insert = ->(*) { raise ActiveRecord::StatementInvalid, "sensitive-sql-value" }
    Rails.stub(:logger, logger) do
      ApiRequestLog.stub(:create!, failing_insert) do
        assert_no_difference("ApiRequestLog.count") do
          get "/api/items", headers: @authorization
          assert_response :success
          assert_equal [@item.id], response.parsed_body["items"].map { |item| item["id"] }
        end
      end
    end
    assert_includes output.string, "API request audit failed: ActiveRecord::StatementInvalid"
    assert_not_includes output.string, "sensitive-sql-value"
    assert_not_includes output.string, @token
  end

  # ----------------------------------------------------------------------------
  test "spoof rejection by Rails request logging still produces an audit row" do
    headers = @authorization.merge(
      "REMOTE_ADDR" => "127.0.0.1",
      "Client-Ip" => "198.51.100.21",
      "X-Forwarded-For" => "203.0.113.42"
    )
    # Enable the real Started request message, which lazily resolves remote_ip.
    logger = ActiveSupport::Logger.new(StringIO.new)
    logger.level = Logger::INFO
    Rails.stub(:logger, logger) do
      assert_difference("ApiRequestLog.count", 1) do
        assert_raises(ActionDispatch::RemoteIp::IpSpoofAttackError) do
          get "/api/items", headers: headers
        end
      end
    end
    row = ApiRequestLog.order(:id).last
    # Rails 7.1 leaves this class at ExceptionWrapper's default server-error status.
    assert_equal [500, "127.0.0.1", nil], [row.status, row.peer_ip, row.remote_ip]
    assert_equal "ActionDispatch::RemoteIp::IpSpoofAttackError", row.exception_class
    assert_equal "ActionDispatch::RemoteIp::IpSpoofAttackError", row.ip_resolution_exception_class
    assert_equal Digest::SHA256.hexdigest(@token), row.token_fingerprint
    assert_not_includes row.attributes.to_json, @token
  end
end
