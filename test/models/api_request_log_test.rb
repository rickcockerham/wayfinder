require "test_helper"

class ApiRequestLogTest < ActiveSupport::TestCase
  # ----------------------------------------------------------------------------
  test "valid diagnostics persist without a user and reject unusable metadata" do
    row = ApiRequestLog.create!(
      requested_at: Time.now.utc, request_id: "model-audit-fixture",
      http_method: "GET", path: "/api/items", status: 401,
      duration_ms: 1.25, authentication_method: "anonymous"
    )
    assert row.persisted?
    assert_nil row.user
    assert_nil row.token_fingerprint

    # Enforce compact, nonsecret credential references and meaningful result values.
    row.assign_attributes(status: 99, duration_ms: -1, authentication_method: "unknown", token_fingerprint: "Bearer usable-secret")
    assert_not row.valid?
    %i[status duration_ms authentication_method token_fingerprint].each do |attribute|
      assert row.errors[attribute].present?, attribute.to_s
    end
  end
end
