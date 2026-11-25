require "test_helper"
require "api_request_audit"

class ApiRequestAuditMiddlewareTest < ActiveSupport::TestCase
  # ----------------------------------------------------------------------------
  test "escaping Rails exceptions are audited and propagated unchanged" do
    env = Rack::MockRequest.env_for("/api/middleware-fixture")
    env["action_dispatch.request_id"] = "middleware-raised-fixture"
    error = ActionController::RoutingError.new("private error details")
    # ShowExceptions stores this even when test configuration asks it to re-raise.
    env["action_dispatch.exception"] = error
    app = ->(_) { raise error }

    # The middleware must not swallow failures or replace them with its own response.
    raised = assert_raises(ActionController::RoutingError) { ApiRequestAudit.new(app).call(env) }
    assert_same error, raised
    row = ApiRequestLog.order(:id).last
    assert_equal [404, "ActionController::RoutingError", "/api/middleware-fixture"], [row.status, row.exception_class, row.path]
    assert_not_includes row.attributes.to_json, "private error details"
  end

  # ----------------------------------------------------------------------------
  test "returned error status wins over Rails exception metadata" do
    env = Rack::MockRequest.env_for("/api/middleware-fixture")
    env["action_dispatch.request_id"] = "middleware-returned-fixture"
    env["action_dispatch.exception"] = ActionController::RoutingError.new("private error details")
    response = [503, { "Content-Type" => "application/json" }, ["{}"]]

    # Custom exception handlers can intentionally return a different HTTP status.
    actual = ApiRequestAudit.new(->(_) { response }).call(env)
    assert_same response, actual
    assert_equal 503, ApiRequestLog.order(:id).last.status
  end

  # ----------------------------------------------------------------------------
  test "IP spoof metadata preserves peer identity and the original returned status" do
    env = Rack::MockRequest.env_for("/api/middleware-spoof-fixture")
    env.merge!(
      "action_dispatch.request_id" => "middleware-spoof-fixture",
      "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_CLIENT_IP" => "198.51.100.21",
      "HTTP_X_FORWARDED_FOR" => "203.0.113.42"
    )
    response = [207, { "Content-Type" => "application/json" }, ["{}"]]
    stack = ActionDispatch::RemoteIp.new(ApiRequestAudit.new(->(_) { response }))

    # Audit resolution is allowed to fail without replacing a completed response.
    assert_difference("ApiRequestLog.count", 1) do
      assert_same response, stack.call(env)
    end
    row = ApiRequestLog.order(:id).last
    assert_equal [207, "127.0.0.1", nil], [row.status, row.peer_ip, row.remote_ip]
    assert_equal "ActionDispatch::RemoteIp::IpSpoofAttackError", row.ip_resolution_exception_class
    assert_nil row.exception_class
  end
end
