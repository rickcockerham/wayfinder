require "test_helper"

class InventoryApiTest < ActionDispatch::IntegrationTest
  # -----------------------------------------------------------------------------
  setup do
    @user = users(:default_user)
    @shop = @user.shops.create!(name: "Parts supplier")
    @root = @user.locations.create!(name: "Electronics bins")
    @other = User.create!(name: "Other", access_key: "inventory-tests-only")
    @other_location = @other.locations.create!(name: "Private")
    @other_shop = @other.shops.create!(name: "Private")
    @other_stock = @other.inventory_items.create!(name: "Private", shop: @other_shop)
    post login_url, params: { key: @user.access_key }
  end

  # -----------------------------------------------------------------------------
  test "nested paths reuse existing roots and every segment on retries" do
    assert_difference("Location.count", 2) do
      post "/api/locations", params: { location: { root_id: @root.id, path: ["second row", "third bin"] } }, as: :json
      assert_response :created
    end
    leaf = response.parsed_body["location"]
    assert_equal ["Electronics bins", "second row", "third bin"], leaf["path"].map { |n| n["name"] }
    assert_equal 2, response.parsed_body["created_ids"].length
    assert_no_difference("Location.count") do
      post "/api/locations", params: { location: { path: ["Electronics bins", "second row", "third bin"] } }, as: :json
      assert_response :success
      assert_equal [], response.parsed_body["created_ids"]
      assert_equal leaf["id"], response.parsed_body["location"]["id"]
    end
    get "/api/locations/#{leaf['id']}"
    assert_equal leaf, response.parsed_body["location"]
    post "/api/locations", params: { location: { path: ["Electronics Drawers", "bottom left", "top tray", "right side"] } }, as: :json
    assert_response :created
    assert_equal 4, response.parsed_body["location"]["path"].length
  end

  # -----------------------------------------------------------------------------
  test "location lookup returns contextual matches and bounded pages" do
    drawer = @user.locations.create!(name: "Drawers")
    [drawer, @root].each { |parent| @user.locations.create!(name: "middle", parent: parent) }
    get "/api/locations", params: { name: "middle" }
    assert_equal 2, response.parsed_body["locations"].length
    assert_equal 2, response.parsed_body["locations"].map { |l| l["parent_id"] }.uniq.length
    get "/api/locations", params: { name: "middle", parent_id: drawer.id }
    assert_equal 1, response.parsed_body["locations"].length
    get "/api/locations", params: { parent_id: "" }
    assert response.parsed_body["locations"].all? { |l| l["parent_id"].nil? }
    get "/api/locations", params: { limit: 1 }
    cursor = response.parsed_body["next_after_id"]
    assert cursor
    get "/api/locations", params: { after_id: cursor }
    assert response.parsed_body["locations"].all? { |l| l["id"] > cursor }
    assert_not_includes response.parsed_body["locations"].map { |l| l["id"] }, @other_location.id
    get "/api/locations", params: { limit: 101 }
    assert_response :bad_request
    get "/api/inventory_items", params: { after_id: -1 }
    assert_response :bad_request
  end

  # -----------------------------------------------------------------------------
  test "count set retries preserve stock identity reservations and exact decimals" do
    payload = { name: "Resistors", location_id: @root.id, shop_id: @shop.id, unit: "each", qty_have: "12.25" }
    assert_difference("InventoryItem.count", 1) do
      put "/api/inventory_items", params: { inventory_item: payload }, as: :json
      assert_response :created
    end
    stock = response.parsed_body["inventory_item"]
    assert_equal "12.25", stock["qty_have"]
    task = items(:one)
    reservation = task.item_inventories.create!(user: @user, inventory_item_id: stock["id"], qty_reserved: 2)
    2.times do
      assert_no_difference("InventoryItem.count") do
        put "/api/inventory_items", params: { inventory_item: payload }, as: :json
        assert_response :success
        assert_equal stock["id"], response.parsed_body["inventory_item"]["id"]
        assert_equal "set", response.parsed_body["quantity_operation"]
      end
    end
    assert_equal 2, reservation.reload.qty_reserved
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: "0", expected_qty_have: "12.25") }, as: :json
    assert_equal "0.0", response.parsed_body["inventory_item"]["qty_have"]
    get "/api/inventory_items/#{stock['id']}"
    assert_equal @root.id, response.parsed_body["inventory_item"]["location"]["path"].last["id"]
    get "/api/inventory_items", params: { name: "Resistors", location_id: @root.id, include_choices: 1 }
    assert_equal [stock["id"]], response.parsed_body["inventory_items"].map { |row| row["id"] }
    assert_equal [{ "id" => @shop.id, "name" => @shop.name }], response.parsed_body["shops"]
  end

  # -----------------------------------------------------------------------------
  test "stock with same name stays separate by location and metadata conflicts never merge" do
    second = @user.locations.create!(name: "Other bins")
    [@root, second].each do |location|
      put "/api/inventory_items", params: { inventory_item: { name: "Cable", location_id: location.id, shop_id: @shop.id, unit: "m", qty_have: "4" } }, as: :json
      assert_response :created
    end
    get "/api/inventory_items", params: { name: "Cable" }
    assert_equal 2, response.parsed_body["inventory_items"].size
    row = @user.inventory_items.find_by!(location: @root)
    put "/api/inventory_items", params: { inventory_item: { name: "Cable", location_id: @root.id, shop_id: @shop.id, unit: "each", qty_have: "99" } }, as: :json
    assert_response :conflict
    assert_equal 4, row.reload.qty_have
    # MySQL's legacy nullable-location index allows duplicates; require an explicit ID.
    duplicates = 2.times.map { @user.inventory_items.new(name: "Loose", shop: @shop, qty_have: 1).tap { |r| r.save!(validate: false) } }
    payload = { name: "Loose", location_id: nil, shop_id: @shop.id, unit: "", qty_have: "3", expected_qty_have: "1" }
    put "/api/inventory_items", params: { inventory_item: payload }, as: :json
    assert_response :conflict
    # Existing legacy duplicate rows need count-only updates without revalidating name uniqueness.
    put "/api/inventory_items", params: { inventory_item: payload.merge(id: duplicates.first.id) }, as: :json
    assert_response :success
    assert_equal [3, 1], duplicates.map { |r| r.reload.qty_have }
  end

  # -----------------------------------------------------------------------------
  test "cross owner reads paths stock writes and supplied IDs are isolated" do
    ["/api/locations/#{@other_location.id}", "/api/inventory_items/#{@other_stock.id}", "/api/locations?parent_id=#{@other_location.id}", "/api/inventory_items?location_id=#{@other_location.id}"].each do |url|
      get url
      assert_response :not_found
    end
    assert_no_difference("Location.count") do
      post "/api/locations", params: { location: { root_id: @other_location.id, path: ["Forbidden"] } }, as: :json
      assert_response :not_found
    end
    base = { name: "Cable", location_id: @root.id, shop_id: @shop.id, unit: "", qty_have: "5" }
    [{ location_id: @other_location.id }, { shop_id: @other_shop.id }, { id: @other_stock.id }].each do |change|
      put "/api/inventory_items", params: { inventory_item: base.merge(change) }, as: :json
      assert_response :not_found
    end
    assert_equal 0, @other_stock.reload.qty_have
  end

  # -----------------------------------------------------------------------------
  test "invalid inputs do not create partial paths or truncate quantities" do
    [{ path: [] }, { path: ["Valid", ""] }, { path: [" padded "] }, { path: [1] }, { path: ["X"], root_id: "1" }, { path: ["X"], user_id: @other.id }, { path: ["x" * 256] }].each do |input|
      assert_no_difference("Location.count") do
        post "/api/locations", params: { location: input }, as: :json
        assert_response :unprocessable_entity
      end
    end
    base = { name: "Cable", location_id: @root.id, shop_id: @shop.id, unit: "", qty_have: "5" }
    [{ qty_have: -1 }, { qty_have: "1.234" }, { qty_have: "100000000" }, { qty_have: "NaN" }, { qty_delta: "1" }, { user_id: @other.id }, { unit: [] }, { name: "" }].each do |change|
      assert_no_difference("InventoryItem.count") do
        put "/api/inventory_items", params: { inventory_item: base.merge(change) }, as: :json
        assert_response :unprocessable_entity
      end
    end
    post "/api/locations", params: {}
    assert_response :unsupported_media_type
    post "/api/locations", params: {}, as: :json
    assert_response :bad_request
    put "/api/inventory_items", params: '{"inventory_item":', headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :bad_request
  end

  # -----------------------------------------------------------------------------
  test "all routes fail closed anonymously and revoked cookies do not work" do
    delete logout_url
    [[:get, "/api/locations"], [:get, "/api/locations/#{@root.id}"], [:post, "/api/locations"], [:get, "/api/inventory_items"], [:get, "/api/inventory_items/#{@other_stock.id}"], [:put, "/api/inventory_items"]].each do |method, path|
      public_send(method, path, params: { key: @user.access_key }, as: :json)
      assert_response :unauthorized
    end
    post login_url, params: { key: @user.access_key }
    @user.update!(access_key: "revoked-inventory-test")
    get "/api/locations"
    assert_response :unauthorized
  end

  # -----------------------------------------------------------------------------
  test "CSRF is enforced for both mutation routes and responses are private" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get "/api/locations"
    assert_equal "no-store", response.headers["Cache-Control"]
    token = response.headers["X-CSRF-Token"]
    post "/api/locations", params: { location: { path: ["Drawers"] } }, as: :json
    assert_response :unprocessable_entity
    assert_equal "invalid_csrf_token", response.parsed_body["error"]
    post "/api/locations", params: { location: { path: ["Drawers"] } }, headers: { "X-CSRF-Token" => token }, as: :json
    assert_response :created
    payload = { inventory_item: { name: "Cable", location_id: @root.id, shop_id: @shop.id, unit: "", qty_have: "1" } }
    put "/api/inventory_items", params: payload, as: :json
    assert_response :unprocessable_entity
    put "/api/inventory_items", params: payload, headers: { "X-CSRF-Token" => token }, as: :json
    assert_response :created
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
  # -----------------------------------------------------------------------------
  test "assistant lookup finds names aliases full paths zero counts and missing records" do
    row = @user.locations.create!(name: "first row", parent: @root)
    bin = @user.locations.create!(name: "2nd bin", parent: row)
    payload = { name: "DC-DC buck converters", aliases: ["step down modules"], location_id: bin.id, shop_id: @shop.id, unit: "each", qty_have: "0" }
    put "/api/inventory_items", params: { inventory_item: payload }, as: :json
    assert_response :created
    id = response.parsed_body["inventory_item"]["id"]
    ["buck", "step down modules"].each do |query|
      get "/api/inventory_items", params: { q: query }
      stock = response.parsed_body["inventory_items"].sole
      assert_equal id, stock["id"]
      assert_equal "0.0", stock["qty_have"]
      assert_equal ["Electronics bins", "first row", "2nd bin"], stock["location"]["path"].map { |n| n["name"] }
      assert_not stock.key?("user_id")
    end
    get "/api/inventory_items", params: { q: "555 timers" }
    assert_empty response.parsed_body["inventory_items"]
    get "/api/inventory_items", params: { location_id: @root.id }
    assert_empty response.parsed_body["inventory_items"]
    # A stale recount cannot overwrite a newer count; repeats are safe no-ops.
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: "8", expected_qty_have: "0") }, as: :json
    assert_response :success
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: "9", expected_qty_have: "0") }, as: :json
    assert_response :conflict
    assert_equal "stale_count", response.parsed_body["error"]
    assert_equal 8, InventoryItem.find(id).qty_have
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: "8", expected_qty_have: "0") }, as: :json
    assert_response :success
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: "9") }, as: :json
    assert_response :conflict
    put "/api/inventory_items", params: { inventory_item: payload.except(:qty_have) }, as: :json
    assert_response :success
    assert_equal "8.0", response.parsed_body["inventory_item"]["qty_have"]
    put "/api/inventory_items", params: { inventory_item: payload.merge(aliases: [1]) }, as: :json
    assert_response :unprocessable_entity
  end

  # -----------------------------------------------------------------------------
  test "presence-only capture preserves known counts and explicit null transitions are stale checked" do
    post "/api/locations", params: { location: { root_id: @root.id, path: ["first row", "2nd bin"] } }, as: :json
    location_id = response.parsed_body["location"]["id"]
    payload = { name: "555 timers", aliases: ["NE555"], location_id: location_id, shop_id: @shop.id, unit: "each" }
    put "/api/inventory_items", params: { inventory_item: payload }, as: :json
    assert_response :created
    assert_equal "record_presence", response.parsed_body["quantity_operation"]
    stock = response.parsed_body["inventory_item"]
    id = stock["id"]
    assert_nil stock["qty_have"]
    assert_equal "unknown", stock["quantity_status"]
    assert_equal ["Electronics bins", "first row", "2nd bin"], stock["location"]["path"].map { |n| n["name"] }
    assert_no_difference("InventoryItem.count") do
      put "/api/inventory_items", params: { inventory_item: payload }, as: :json
      assert_response :success
      assert_equal "preserve", response.parsed_body["quantity_operation"]
      assert_nil response.parsed_body["inventory_item"]["qty_have"]
    end
    get "/api/inventory_items", params: { q: "NE555" }
    assert_equal [id], response.parsed_body["inventory_items"].map { |s| s["id"] }
    get "/api/inventory_items/#{id}"
    assert_equal "unknown", response.parsed_body["inventory_item"]["quantity_status"]
    # Explicit null also creates an unknown presence record rather than numeric zero.
    put "/api/inventory_items", params: { inventory_item: payload.merge(name: "Unknown comparator", qty_have: nil) }, as: :json
    assert_response :created
    assert_equal "record_presence", response.parsed_body["quantity_operation"]
    assert_nil response.parsed_body["inventory_item"]["qty_have"]
    # An absent expectation and an explicit unknown expectation are distinct.
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: "5") }, as: :json
    assert_response :conflict
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: "5", expected_qty_have: nil) }, as: :json
    assert_response :success
    assert_equal "set", response.parsed_body["quantity_operation"]
    assert_equal "positive", response.parsed_body["inventory_item"]["quantity_status"]
    2.times do
      put "/api/inventory_items", params: { inventory_item: payload }, as: :json
      assert_response :success
      assert_equal "5.0", response.parsed_body["inventory_item"]["qty_have"]
      assert_equal "preserve", response.parsed_body["quantity_operation"]
    end
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: nil) }, as: :json
    assert_response :conflict
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: nil, expected_qty_have: "4") }, as: :json
    assert_response :conflict
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: nil, expected_qty_have: "5") }, as: :json
    assert_response :success
    assert_equal "clear_to_unknown", response.parsed_body["quantity_operation"]
    assert_nil response.parsed_body["inventory_item"]["qty_have"]
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: "0", expected_qty_have: "5") }, as: :json
    assert_response :conflict
    put "/api/inventory_items", params: { inventory_item: payload.merge(qty_have: "0", expected_qty_have: nil) }, as: :json
    assert_response :success
    assert_equal "zero", response.parsed_body["inventory_item"]["quantity_status"]
    put "/api/inventory_items", params: { inventory_item: payload }, as: :json
    assert_equal "0.0", response.parsed_body["inventory_item"]["qty_have"]
    assert_equal 1, @user.inventory_items.where(name: "555 timers").count
  end

  # -----------------------------------------------------------------------------
  test "totals separate units and unknown portions across all filtered pages and owners" do
    locations = 4.times.map { |i| @user.locations.create!(name: "Summary #{i}", parent: @root) }
    [nil, 0, 2.5].zip(locations).each do |qty, location|
      @user.inventory_items.create!(name: "Timers", location: location, shop: @shop, unit: "each", qty_have: qty)
    end
    @user.inventory_items.create!(name: "Timers", location: locations.last, shop: @shop, unit: "box", qty_have: 3)
    @other.inventory_items.create!(name: "Timers", shop: @other_shop, unit: "each", qty_have: nil)
    get "/api/inventory_items", params: { q: "Timers", include_totals: 1, limit: 1 }
    assert_response :success
    assert_equal 1, response.parsed_body["inventory_items"].size
    totals = response.parsed_body["totals"]
    each = totals.find { |row| row["unit"] == "each" }
    assert_equal "2.5", each["known_quantity"]
    assert_equal 2, each["known_rows"]
    assert_equal 1, each["unknown_rows"]
    assert_equal false, each["complete"]
    assert_equal true, totals.find { |row| row["unit"] == "box" }["complete"]
    get "/api/inventory_items", params: { location_id: locations.first.id, include_totals: 1 }
    assert_nil response.parsed_body["totals"].sole["known_quantity"]
    assert_equal 1, response.parsed_body["totals"].sole["unknown_rows"]
    get "/api/inventory_items", params: { q: "Not recorded", include_totals: 1 }
    assert_empty response.parsed_body["inventory_items"]
    assert_empty response.parsed_body["totals"]
  end

  # -----------------------------------------------------------------------------
  test "unknown captures and count clears cannot access foreign stock locations or shops" do
    payload = { name: "Present part", location_id: @root.id, shop_id: @shop.id, unit: "each" }
    [{ id: @other_stock.id }, { location_id: @other_location.id }, { shop_id: @other_shop.id }].each do |change|
      [payload, payload.merge(qty_have: nil, expected_qty_have: "0")].each do |input|
        assert_no_difference("InventoryItem.count") do
          put "/api/inventory_items", params: { inventory_item: input.merge(change) }, as: :json
          assert_response :not_found
        end
      end
    end
    assert_equal 0, @other_stock.reload.qty_have
    delete logout_url
    put "/api/inventory_items", params: { inventory_item: payload }, as: :json
    assert_response :unauthorized
  end

end
