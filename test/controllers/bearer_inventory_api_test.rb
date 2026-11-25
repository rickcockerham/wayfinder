require "test_helper"
require "digest"

class BearerInventoryApiTest < ActionDispatch::IntegrationTest
  # ----------------------------------------------------------------------------
  setup do
    # Exercise the real CSRF callbacks with deterministic, fixture-only credentials.
    @saved_environment = %w[WAYFINDER_API_TOKEN_SHA256 WAYFINDER_API_USER_ID].to_h { |key| [key, ENV[key]] }
    @saved_forgery_protection = ActionController::Base.allow_forgery_protection
    @user = users(:default_user)
    @shop = @user.shops.create!(name: "Bearer parts supplier")
    @root = @user.locations.create!(name: "Bearer electronics bins")
    @stock = @user.inventory_items.create!(name: "Fixture timer", aliases: ["NE555 fixture"], shop: @shop, location: @root, unit: "each", qty_have: nil)
    @other = User.create!(name: "Other inventory owner", access_key: "bearer-inventory-other-fixture-only")
    @other_shop = @other.shops.create!(name: "Private supplier")
    @other_location = @other.locations.create!(name: "Private bins")
    @other_stock = @other.inventory_items.create!(name: "Private timer", shop: @other_shop, location: @other_location, unit: "each", qty_have: 4)
    @token = "wayfinder-inventory-fixture-only-#{'5e' * 24}"
    @authorization = { "Authorization" => "Bearer #{@token}" }
    ENV["WAYFINDER_API_TOKEN_SHA256"] = Digest::SHA256.hexdigest(@token)
    ENV["WAYFINDER_API_USER_ID"] = @user.id.to_s
    ActionController::Base.allow_forgery_protection = true
  end

  # ----------------------------------------------------------------------------
  teardown do
    # Restore process settings for the existing session and items API tests.
    @saved_environment&.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    ActionController::Base.allow_forgery_protection = @saved_forgery_protection
  end

  # ----------------------------------------------------------------------------
  test "bearer creates and reuses nested paths without cookies or CSRF tokens" do
    payload = { location: { root_id: @root.id, path: ["second row", "third bin"] } }
    assert_difference("Location.count", 2) do
      post "/api/locations", params: payload, headers: @authorization, as: :json
      assert_response :created
    end
    leaf = response.parsed_body["location"]
    assert_equal [@root.name, "second row", "third bin"], leaf["path"].map { |node| node["name"] }
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.headers["X-CSRF-Token"]

    # Repeating the same capture retains the stable location identity.
    assert_no_difference("Location.count") do
      post "/api/locations", params: payload, headers: @authorization, as: :json
      assert_response :success
      assert_equal leaf["id"], response.parsed_body["location"]["id"]
      assert_empty response.parsed_body["created_ids"]
    end
    get "/api/locations/#{leaf['id']}", headers: @authorization
    assert_response :success
    assert_equal leaf, response.parsed_body["location"]
    get "/api/locations"
    assert_response :unauthorized
  end

  # ----------------------------------------------------------------------------
  test "bearer preserves unknown presence and rejects stale recounts atomically" do
    payload = { name: "Bearer captured modules", aliases: ["step down fixture"], location_id: @root.id, shop_id: @shop.id, unit: "each" }
    assert_difference("InventoryItem.count", 1) do
      put "/api/inventory_items", params: { inventory_item: payload }, headers: @authorization, as: :json
      assert_response :created
    end
    captured_id = response.parsed_body["inventory_item"]["id"]
    assert_nil response.parsed_body["inventory_item"]["qty_have"]
    assert_equal "record_presence", response.parsed_body["quantity_operation"]

    # Only an explicit unknown expectation can replace an unknown count.
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: "8.25") }, headers: @authorization, as: :json
    assert_response :conflict
    assert_equal "stale_count", response.parsed_body["error"]
    assert_nil InventoryItem.find(captured_id).qty_have
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: "8.25", expected_qty_have: nil) }, headers: @authorization, as: :json
    assert_response :success
    assert_equal "8.25", response.parsed_body["inventory_item"]["qty_have"]

    # Presence capture preserves the observed balance and aliases remain searchable.
    put "/api/inventory_items", params: { inventory_item: payload }, headers: @authorization, as: :json
    assert_response :success
    assert_equal "preserve", response.parsed_body["quantity_operation"]
    assert_equal "8.25", response.parsed_body["inventory_item"]["qty_have"]
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: "6", expected_qty_have: "8") }, headers: @authorization, as: :json
    assert_response :conflict
    assert_equal "stale_count", response.parsed_body["error"]
    assert_equal "8.25", InventoryItem.find(captured_id).qty_have.to_s("F")

    # Explicit clearing also compares the last known balance instead of inventing zero.
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: nil, expected_qty_have: "8.25") }, headers: @authorization, as: :json
    assert_response :success
    assert_equal captured_id, response.parsed_body["inventory_item"]["id"]
    assert_nil response.parsed_body["inventory_item"]["qty_have"]
    assert_equal "clear_to_unknown", response.parsed_body["quantity_operation"]
    get "/api/inventory_items", params: { q: "step down fixture" }, headers: @authorization
    assert_equal [captured_id], response.parsed_body["inventory_items"].map { |row| row["id"] }
  end

  # ----------------------------------------------------------------------------
  test "bearer inventory lookups and supplied associations remain owner scoped" do
    get "/api/inventory_items", params: { q: "timer", include_choices: 1, include_totals: 1 }, headers: @authorization
    assert_response :success
    assert_equal [@stock.id], response.parsed_body["inventory_items"].map { |row| row["id"] }
    assert_equal [@shop.id], response.parsed_body["shops"].map { |row| row["id"] }
    assert_equal 1, response.parsed_body["totals"].sole["unknown_rows"]
    assert_equal [@root.id], response.parsed_body["inventory_items"].sole["location"]["path"].map { |node| node["id"] }

    # Foreign IDs fail identically for individual reads and filtering.
    ["/api/locations/#{@other_location.id}", "/api/inventory_items/#{@other_stock.id}", "/api/locations?parent_id=#{@other_location.id}", "/api/inventory_items?location_id=#{@other_location.id}"].each do |path|
      get path, headers: @authorization
      assert_response :not_found
    end
    assert_no_difference("Location.count") do
      post "/api/locations", params: { location: { root_id: @other_location.id, path: ["Forbidden"] } }, headers: @authorization, as: :json
      assert_response :not_found
    end
    payload = { name: "Forbidden capture", location_id: @root.id, shop_id: @shop.id, unit: "each" }
    [{ location_id: @other_location.id }, { shop_id: @other_shop.id }, { id: @other_stock.id }].each do |change|
      assert_no_difference("InventoryItem.count") do
        put "/api/inventory_items", params: { inventory_item: payload.merge(change) }, headers: @authorization, as: :json
        assert_response :not_found
      end
    end
    assert_equal 4, @other_stock.reload.qty_have
  end

  # ----------------------------------------------------------------------------
  test "explicit bearer identity overrides cookies and invalid headers never fall back" do
    # Establish the other owner's real browser session while CSRF is enabled.
    get login_url
    login_csrf = css_select('meta[name="csrf-token"]').first["content"]
    post login_url, params: { key: @other.access_key, authenticity_token: login_csrf }
    assert_redirected_to root_url
    get "/api/inventory_items", headers: @authorization
    assert_response :success
    assert_equal [@stock.id], response.parsed_body["inventory_items"].map { |row| row["id"] }

    ["", "Bearer wrong", "Basic #{@token}"].each do |header|
      assert_no_difference("Location.count") do
        post "/api/locations", params: { location: { path: ["Rejected path"] } }, headers: { "Authorization" => header }, as: :json
        assert_response :unauthorized
        assert_equal "no-store", response.headers["Cache-Control"]
      end
    end

    # Cookie authentication retains its owner and still requires the browser CSRF token.
    get "/api/inventory_items"
    assert_response :success
    assert_equal [@other_stock.id], response.parsed_body["inventory_items"].map { |row| row["id"] }
    csrf = response.headers["X-CSRF-Token"]
    assert csrf.present?
    payload = { location: { path: ["Cookie protected path"] } }
    assert_no_difference("Location.count") do
      post "/api/locations", params: payload, as: :json
      assert_response :unprocessable_entity
      assert_equal "invalid_csrf_token", response.parsed_body["error"]
    end
    post "/api/locations", params: payload, headers: { "X-CSRF-Token" => csrf }, as: :json
    assert_response :created
    assert_equal @other.id, Location.find(response.parsed_body["location"]["id"]).user_id

    ENV.delete("WAYFINDER_API_TOKEN_SHA256")
    get "/api/inventory_items", headers: @authorization
    assert_response :unauthorized
  end

  # ----------------------------------------------------------------------------
  test "inventory audit records verified bearer identity without retaining secrets or payloads" do
    private_name = "Private stock capture body fixture"
    headers = @authorization.merge("X-Request-Id" => "inventory-bearer-audit-fixture")
    assert_difference("ApiRequestLog.count", 1) do
      put "/api/inventory_items", params: { inventory_item: { name: private_name, location_id: @root.id, shop_id: @shop.id, unit: "each" } }, headers: headers, as: :json
      assert_response :created
    end
    row = ApiRequestLog.find_by!(request_id: "inventory-bearer-audit-fixture")
    assert_equal [@user.id, "bearer", Digest::SHA256.hexdigest(@token)], [row.user_id, row.authentication_method, row.token_fingerprint]
    assert_equal ["PUT", "/api/inventory_items", 201], [row.http_method, row.path, row.status]
    [@token, @user.access_key, private_name, "Authorization"].each do |secret|
      assert_not_includes row.attributes.to_json, secret
    end

    # Query strings and malformed request bodies also remain outside the audit record.
    get "/api/inventory_items", params: { q: @token }, headers: @authorization
    assert_response :success
    assert_not_includes ApiRequestLog.order(:id).last.attributes.to_json, @token
    put "/api/inventory_items", params: '{"inventory_item":', headers: @authorization.merge("Content-Type" => "application/json")
    assert_response :bad_request
    assert_equal "invalid_json", response.parsed_body["error"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end
end
