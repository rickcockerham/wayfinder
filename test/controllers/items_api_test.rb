require "test_helper"
require "minitest/mock"

class ItemsApiTest < ActionDispatch::IntegrationTest
  # --------------------------------------------------------------------------
  setup do
    @user = users(:default_user)
    @item = items(:one)
    @other = User.create!(name: "Other fixture", access_key: "isolated-test-only")
    @other_category = @other.categories.create!(name: "Other")
    @other_mood = @other.moods.create!(name: "Other")
    @other_item = @other.items.create!(title: "Private", category: @other_category, mood: @other_mood)
    post login_url, params: { key: @user.access_key }
  end

  # --------------------------------------------------------------------------
  test "every action requires authentication and does not accept query keys" do
    delete logout_url
    [[:get, "/api/items"], [:get, "/api/items/#{@item.id}"], [:post, "/api/items"], [:patch, "/api/items/#{@item.id}"], [:delete, "/api/items/#{@item.id}"]].each do |method, path|
      public_send(method, path, params: { item: { title: "Forbidden" } }, as: :json)
      assert_response :unauthorized
      assert_equal "unauthorized", response.parsed_body["error"]
    end
    get "/api/items", params: { key: @user.access_key }
    assert_response :unauthorized
  end

  # --------------------------------------------------------------------------
  test "list is compact bounded and private and read is complete" do
    get "/api/items", params: { limit: 1 }
    assert_response :success
    assert_equal [@item.id], response.parsed_body["items"].map { |row| row["id"] }
    assert_not response.parsed_body["items"].first.key?("notes")
    assert_equal "no-store", response.headers["Cache-Control"]
    assert response.headers["X-CSRF-Token"].present?
    get "/api/items/#{@item.id}"
    assert_equal @item.title, response.parsed_body["item"]["title"]
    assert response.parsed_body["item"].key?("notes")
    assert_not response.parsed_body["item"].key?("user_id")
    get "/api/items", params: { limit: 101 }
    assert_response :bad_request
    get "/api/items", params: { after_id: -1 }
    assert_response :bad_request
  end

  # --------------------------------------------------------------------------
  test "cross user reads updates deletes and associations are isolated" do
    [[:get, {}], [:patch, { item: { title: "Changed" } }], [:delete, {}]].each do |method, payload|
      public_send(method, "/api/items/#{@other_item.id}", params: payload, as: :json)
      assert_response :not_found
    end
    %w[category_id mood_id parent_id].zip([@other_category.id, @other_mood.id, @other_item.id]).each do |field, id|
      patch "/api/items/#{@item.id}", params: { item: { field => id } }, as: :json
      assert_response :unprocessable_entity
    end
    assert_equal "Private", @other_item.reload.title
  end

  # --------------------------------------------------------------------------
  test "capture defaults are zero and no deadline while explicit values survive partial updates" do
    post "/api/items", params: { item: { title: "Capture", category_id: @item.category_id, mood_id: @item.mood_id } }, as: :json
    assert_response :created
    row = response.parsed_body["item"]
    assert_equal [0, 0, 0, nil], row.values_at("personal_impact", "emotional_impact", "family_impact", "deadline")
    id = row["id"]
    patch "/api/items/#{id}", params: { item: { personal_impact: 5, emotional_impact: 2, family_impact: 1, deadline: "2027-01-02", notes: "Keep me" } }, as: :json
    assert_response :success
    patch "/api/items/#{id}", params: { item: { title: "Renamed" } }, as: :json
    assert_equal [5, 2, 1, "2027-01-02", "Keep me"], response.parsed_body["item"].values_at("personal_impact", "emotional_impact", "family_impact", "deadline", "notes")
    patch "/api/items/#{id}", params: { item: { deadline: "" } }, as: :json
    assert_nil response.parsed_body["item"]["deadline"]
  end

  # --------------------------------------------------------------------------
  test "validation rejects missing associations malformed values and mass assignment" do
    post "/api/items", params: { item: { title: "Title only" } }, as: :json
    assert_response :unprocessable_entity
    [{ title: "" }, { personal_impact: 6 }, { family_impact: nil }, { emotional_impact: "1" }, { time_scale: 8 }, { hide_days: -1 }, { deadline: "2026-02-31" }, { done: "false" }, { recurrence_kind: "invalid" }, { recurrence_interval: 0 }, { user_id: @other.id }, { title: [] }, { title: "x" * 256 }, { hide_days: 2**40 }, { parent_id: @item.id }].each do |attributes|
      patch "/api/items/#{@item.id}", params: { item: attributes }, as: :json
      assert_response :unprocessable_entity, attributes.inspect
    end
    patch "/api/items/#{@item.id}", params: {}, as: :json
    assert_response :bad_request
    patch "/api/items/#{@item.id}", params: { item: { title: "form" } }
    assert_response :unsupported_media_type
    patch "/api/items/#{@item.id}", params: '{"item":', headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :bad_request
    assert_equal "Default item", @item.reload.title
  end

  # --------------------------------------------------------------------------
  test "completion recurrence and reactivation preserve lifecycle" do
    patch "/api/items/#{@item.id}", params: { item: { done: true } }, as: :json
    assert_response :success
    assert @item.reload.completed_at
    patch "/api/items/#{@item.id}", params: { item: { done: false } }, as: :json
    assert_response :success
    assert_nil @item.reload.completed_at
    @item.update!(deadline: "2026-06-09", recurrence_kind: :fixed_schedule, recurrence_unit: :week, recurrence_interval: 2)
    patch "/api/items/#{@item.id}", params: { item: { done: true } }, as: :json
    assert_response :success
    assert_equal Date.new(2026, 6, 23), @item.reload.deadline
    assert_not @item.done?
    assert_nil @item.completed_at
  end

  # --------------------------------------------------------------------------
  test "delete uses existing dependent behavior on isolated fixtures" do
    child = @user.items.create!(title: "Child", category: @item.category, mood: @item.mood, parent: @item)
    assert_difference("Item.count", -1) do
      delete "/api/items/#{@item.id}", as: :json
      assert_response :success
    end
    assert_equal @item.id, response.parsed_body["deleted"]
    assert_nil child.reload.parent_id
    get "/api/items/#{@item.id}"
    assert_response :not_found
  end

  # --------------------------------------------------------------------------
  test "session mutations require CSRF token when protection is enabled" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get "/api/items"
    token = response.headers["X-CSRF-Token"]
    patch "/api/items/#{@item.id}", params: { item: { title: "Rejected" } }, as: :json
    assert_response :unprocessable_entity
    assert_equal "invalid_csrf_token", response.parsed_body["error"]
    patch "/api/items/#{@item.id}", params: { item: { title: "Accepted" } }, headers: { "X-CSRF-Token" => token }, as: :json
    assert_response :success
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
  # --------------------------------------------------------------------------
  test "pagination traverses owned items only and revoked cookies fail closed" do
    second = @user.items.create!(title: "Second", category: @item.category, mood: @item.mood)
    get "/api/items", params: { limit: 1 }
    cursor = response.parsed_body["next_after_id"]
    assert_equal [@item.id, second.id].min, cursor
    get "/api/items", params: { limit: 1, after_id: cursor }
    assert_equal [[@item.id, second.id].max], response.parsed_body["items"].map { |row| row["id"] }
    assert_nil response.parsed_body["next_after_id"]
    @user.update!(access_key: "revoked-test-only")
    get "/api/items"
    assert_response :unauthorized
  end

  # --------------------------------------------------------------------------
  test "completion consumes reservations once and rollback preserves item on failure" do
    shop = @user.shops.create!(name: "Fixture shop")
    inventory = @user.inventory_items.create!(name: "Fixture inventory", qty_have: 5, shop: shop)
    @item.item_inventories.create!(user: @user, inventory_item: inventory, qty_reserved: 2)
    patch "/api/items/#{@item.id}", params: { item: { done: true } }, as: :json
    assert_response :success
    assert_equal 3, inventory.reload.qty_have
    assert_empty @item.item_inventories.reload
    patch "/api/items/#{@item.id}", params: { item: { done: true } }, as: :json
    assert_equal 3, inventory.reload.qty_have
    patch "/api/items/#{@item.id}", params: { item: { done: false } }, as: :json
    @item.item_inventories.create!(user: @user, inventory_item: inventory, qty_reserved: 1)
    RecurrenceAdvancer.stub(:new, ->(_) { raise "isolated failure" }) do
      patch "/api/items/#{@item.id}", params: { item: { done: true } }, as: :json
    end
    assert_response :internal_server_error
    assert_equal "mutation_failed", response.parsed_body["error"]
    assert_equal 3, inventory.reload.qty_have
    assert_equal 1, @item.item_inventories.reload.first.qty_reserved
    assert_not @item.reload.done?
    assert_nil @item.completed_at
  end
  # --------------------------------------------------------------------------
  test "item create choices include unused visible owned names only when requested" do
    category = @user.categories.create!(name: "Unused category")
    mood = @user.moods.create!(name: "Unused mood")
    hidden_category = @user.categories.create!(name: "Hidden category", hidden: true)
    hidden_mood = @user.moods.create!(name: "Hidden mood", hidden: true)
    get "/api/items"
    assert_not response.parsed_body.key?("choices")
    get "/api/items", params: { include_choices: 1 }
    assert_response :success
    choices = response.parsed_body["choices"]
    assert_includes choices["categories"], { "id" => category.id, "name" => category.name }
    assert_includes choices["moods"], { "id" => mood.id, "name" => mood.name }
    assert_not_includes choices["categories"].map { |row| row["id"] }, hidden_category.id
    assert_not_includes choices["moods"].map { |row| row["id"] }, hidden_mood.id
    assert_not_includes choices["categories"].map { |row| row["id"] }, @other_category.id
    assert_not_includes choices["moods"].map { |row| row["id"] }, @other_mood.id
    assert_equal ["id", "name"], choices["categories"].first.keys.sort
    post "/api/items", params: { item: { title: "Assistant enriched task", category_id: category.id, mood_id: mood.id } }, as: :json
    assert_response :created
    assert_equal [category.id, mood.id, 0, 0, 0, nil], response.parsed_body["item"].values_at("category_id", "mood_id", "personal_impact", "emotional_impact", "family_impact", "deadline")
  end

  # --------------------------------------------------------------------------
  test "create choices are available to an owner with no items and never anonymously" do
    @other_item.destroy!
    post login_url, params: { key: @other.access_key }
    get "/api/items", params: { include_choices: 1 }
    assert_response :success
    assert_empty response.parsed_body["items"]
    assert_equal [{ "id" => @other_category.id, "name" => @other_category.name }], response.parsed_body.dig("choices", "categories")
    assert_equal [{ "id" => @other_mood.id, "name" => @other_mood.name }], response.parsed_body.dig("choices", "moods")
    delete logout_url
    get "/api/items", params: { include_choices: 1 }
    assert_response :unauthorized
    assert_not response.parsed_body.key?("choices")
  end
end
