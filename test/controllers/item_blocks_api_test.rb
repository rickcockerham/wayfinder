require "test_helper"
require "digest"

class ItemBlocksApiTest < ActionDispatch::IntegrationTest
  #-----------------------------------------------------------------------------
  setup do
    @saved_environment = %w[WAYFINDER_API_TOKEN_SHA256 WAYFINDER_API_USER_ID].to_h { |key| [key, ENV[key]] }
    @saved_forgery_protection = ActionController::Base.allow_forgery_protection
    @user = users(:default_user)
    @a, @b, @c, @d = %w[A B C D].map { |label| @user.items.create!(title: "Block fixture #{label}", category: categories(:default_category), mood: moods(:default_mood)) }
    @other = User.create!(name: "Other blocker fixture", access_key: "blocker-other-test-only")
    @private = @other.items.create!(title: "Private task", category: @other.categories.create!(name: "Private"), mood: @other.moods.create!(name: "Private"))
    @private_edge = @other.item_blocks.create!(blocker: @private, blocked: @other.items.create!(title: "Private dependent", category: @private.category, mood: @private.mood))
    @token = "d" * 64
    @authorization = { "Authorization" => "Bearer #{@token}" }
    ENV["WAYFINDER_API_TOKEN_SHA256"] = Digest::SHA256.hexdigest(@token)
    ENV["WAYFINDER_API_USER_ID"] = @user.id.to_s
    ActionController::Base.allow_forgery_protection = true
  end

  #-----------------------------------------------------------------------------
  teardown do
    @saved_environment.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    ActionController::Base.allow_forgery_protection = @saved_forgery_protection
  end

  #-----------------------------------------------------------------------------
  test "create read both directions paginate repeat and remove native blocker" do
    payload = { item_block: { blocker_id: @a.id, blocked_id: @b.id } }
    assert_difference("ItemBlock.count", 1) do
      post "/api/item_blocks", params: payload, headers: @authorization, as: :json
      assert_response :created
    end
    edge = response.parsed_body.fetch("item_block")
    assert_equal [@a.id, @b.id, true], edge.values_at("blocker_id", "blocked_id", "active")
    assert_equal @a.title, edge["blocker"]["title"]
    assert_equal @b.title, edge["blocked"]["title"]
    assert_not edge.key?("user_id")
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.headers["X-CSRF-Token"]
    assert_no_difference("ItemBlock.count") do
      post "/api/item_blocks", params: payload, headers: @authorization, as: :json
      assert_response :success
      assert_equal edge["id"], response.parsed_body["item_block"]["id"]
    end
    get "/api/item_blocks/#{edge['id']}", headers: @authorization
    assert_equal edge, response.parsed_body["item_block"]
    [ { blocker_id: @a.id }, { blocked_id: @b.id } ].each do |filter|
      get "/api/item_blocks", params: filter, headers: @authorization
      assert_response :success
      assert_equal [edge["id"]], response.parsed_body["item_blocks"].map { |row| row["id"] }
    end
    @user.item_blocks.create!(blocker: @a, blocked: @c)
    get "/api/item_blocks", params: { limit: 1 }, headers: @authorization
    cursor = response.parsed_body["next_after_id"]
    assert cursor
    get "/api/item_blocks", params: { after_id: cursor }, headers: @authorization
    assert response.parsed_body["item_blocks"].all? { |row| row["id"] > cursor }
    assert_not_includes response.parsed_body["item_blocks"].map { |row| row["id"] }, @private_edge.id
    assert_difference("ItemBlock.count", -1) do
      delete "/api/item_blocks/#{edge['id']}", headers: @authorization
      assert_response :success
    end
    assert_equal edge["id"], response.parsed_body["deleted"]
    assert Item.exists?(@a.id)
    assert Item.exists?(@b.id)
    delete "/api/item_blocks/#{edge['id']}", headers: @authorization
    assert_response :not_found
  end

  #-----------------------------------------------------------------------------
  test "completed blockers retain links but no longer block readiness or home eligibility" do
    edge = @user.item_blocks.create!(blocker: @a, blocked: @b)
    assert_not @b.ready_now?(inventory_hash: {})
    assert_not_includes @user.items.without_active_blockers.pluck(:id), @b.id
    get "/api/items/priorities", params: { limit: 100, category_id: "" }, headers: @authorization
    assert_not_includes response.parsed_body["items"].map { |row| row["id"] }, @b.id
    patch "/api/items/#{@a.id}", params: { item: { done: true } }, headers: @authorization, as: :json
    assert_response :success
    get "/api/item_blocks/#{edge.id}", headers: @authorization
    assert_equal false, response.parsed_body["item_block"]["active"]
    assert @b.reload.ready_now?(inventory_hash: {})
    get "/api/items/priorities", params: { limit: 100, category_id: "" }, headers: @authorization
    assert_includes response.parsed_body["items"].map { |row| row["id"] }, @b.id
    patch "/api/items/#{@a.id}", params: { item: { done: false } }, headers: @authorization, as: :json
    assert_not @b.reload.ready_now?(inventory_hash: {})
    assert ItemBlock.exists?(edge.id)
    delete "/api/item_blocks/#{edge.id}", headers: @authorization
    assert @b.reload.ready_now?(inventory_hash: {})
  end

  #-----------------------------------------------------------------------------
  test "self links cycles malformed input and stale endpoints are rejected" do
    @user.item_blocks.create!(blocker: @a, blocked: @b)
    @user.item_blocks.create!(blocker: @b, blocked: @c)
    [ { blocker_id: @c.id, blocked_id: @a.id }, { blocker_id: @a.id, blocked_id: @a.id },
      { blocker_id: @a.id.to_s, blocked_id: @b.id }, { blocker_id: nil, blocked_id: @b.id },
      { blocker_id: @a.id, blocked_id: @d.id, user_id: @other.id } ].each do |input|
      assert_no_difference("ItemBlock.count") do
        post "/api/item_blocks", params: { item_block: input }, headers: @authorization, as: :json
        assert_response :unprocessable_entity
      end
    end
    stale_id = @d.id
    @d.destroy!
    post "/api/item_blocks", params: { item_block: { blocker_id: @a.id, blocked_id: stale_id } }, headers: @authorization, as: :json
    assert_response :not_found
    get "/api/item_blocks", params: { blocked_id: stale_id }, headers: @authorization
    assert_response :not_found
    get "/api/item_blocks", params: { limit: 101 }, headers: @authorization
    assert_response :bad_request
    ["", "abc", "0", [@a.id.to_s], { bad: @a.id }].each do |value|
      get "/api/item_blocks", params: { blocker_id: value }, headers: @authorization
      assert_response :bad_request
      assert_equal "invalid_filter", response.parsed_body["error"]
    end
    post "/api/item_blocks", params: {}, headers: @authorization, as: :json
    assert_response :bad_request
    post "/api/item_blocks", params: { item_block: { blocker_id: @a.id, blocked_id: @d.id } }, headers: @authorization
    assert_response :unsupported_media_type
    post "/api/item_blocks", params: '{"item_block":', headers: @authorization.merge("CONTENT_TYPE" => "application/json")
    assert_response :bad_request
  end

  #-----------------------------------------------------------------------------
  test "all graph operations isolate owners and bearer errors do not fall back to sessions" do
    [[:get, "/api/item_blocks"], [:get, "/api/item_blocks/#{@private_edge.id}"], [:post, "/api/item_blocks"], [:delete, "/api/item_blocks/#{@private_edge.id}"]].each do |method, path|
      public_send(method, path, headers: { "Authorization" => "Bearer wrong-fixture-only" }, as: :json)
      assert_response :unauthorized
    end
    get "/api/item_blocks"
    assert_response :unauthorized
    [[:get, "/api/item_blocks/#{@private_edge.id}"], [:delete, "/api/item_blocks/#{@private_edge.id}"], [:get, "/api/item_blocks?blocker_id=#{@private.id}"]].each do |method, path|
      public_send(method, path, headers: @authorization)
      assert_response :not_found
    end
    [ { blocker_id: @private.id, blocked_id: @a.id }, { blocker_id: @a.id, blocked_id: @private.id } ].each do |input|
      post "/api/item_blocks", params: { item_block: input }, headers: @authorization, as: :json
      assert_response :not_found
    end
    assert ItemBlock.exists?(@private_edge.id)
    ActionController::Base.allow_forgery_protection = false
    post login_url, params: { key: @user.access_key }
    ActionController::Base.allow_forgery_protection = true
    get "/api/item_blocks"
    token = response.headers["X-CSRF-Token"]
    post "/api/item_blocks", params: { item_block: { blocker_id: @a.id, blocked_id: @b.id } }, as: :json
    assert_response :unprocessable_entity
    assert_equal "invalid_csrf_token", response.parsed_body["error"]
    post "/api/item_blocks", params: { item_block: { blocker_id: @a.id, blocked_id: @b.id } }, headers: { "X-CSRF-Token" => token }, as: :json
    assert_response :created
    post "/api/item_blocks", params: { item_block: { blocker_id: @a.id, blocked_id: @c.id } }, headers: { "Authorization" => "Bearer wrong-fixture-only", "X-CSRF-Token" => token }, as: :json
    assert_response :unauthorized
  end

  #-----------------------------------------------------------------------------
  test "both supported destroy paths remove only links touching the deleted endpoint" do
    [:api, :web].each do |entry_point|
      project = @user.items.create!(title: "Parent project #{entry_point}", category: @a.category, mood: @a.mood)
      child = @user.items.create!(title: "Surviving child #{entry_point}", category: @a.category, mood: @a.mood, parent: project)
      incoming = @user.item_blocks.create!(blocker: @a, blocked: project)
      outgoing = @user.item_blocks.create!(blocker: project, blocked: @b)
      retained = @user.item_blocks.create!(blocker: child, blocked: @c)
      unrelated = @user.item_blocks.find_or_create_by!(blocker: @c, blocked: @d)
      if entry_point == :api
        delete "/api/items/#{project.id}", headers: @authorization
        assert_response :success
      else
        ActionController::Base.allow_forgery_protection = false
        post login_url, params: { key: @user.access_key }
        delete item_url(project)
        assert_redirected_to items_url
        ActionController::Base.allow_forgery_protection = true
      end
      assert_not ItemBlock.exists?(incoming.id)
      assert_not ItemBlock.exists?(outgoing.id)
      assert ItemBlock.exists?(retained.id)
      assert ItemBlock.exists?(unrelated.id)
      assert ItemBlock.exists?(@private_edge.id)
      [@a, @b, @c, @d, child].each { |item| assert Item.exists?(item.id) }
      assert_nil child.reload.parent_id
      get "/api/item_blocks/#{incoming.id}", headers: @authorization
      assert_response :not_found
      delete "/api/item_blocks/#{outgoing.id}", headers: @authorization
      assert_response :not_found
    end
  end
  #-----------------------------------------------------------------------------
  test "corrupt legacy cross owner links do not leak through index show or delete" do
    corrupt = @user.item_blocks.new(blocker: @a, blocked: @private)
    corrupt.save!(validate: false)
    get "/api/item_blocks", headers: @authorization
    assert_not_includes response.parsed_body["item_blocks"].map { |row| row["id"] }, corrupt.id
    get "/api/item_blocks/#{corrupt.id}", headers: @authorization
    assert_response :not_found
    delete "/api/item_blocks/#{corrupt.id}", headers: @authorization
    assert_response :not_found
    assert ItemBlock.exists?(corrupt.id)
  end

  #-----------------------------------------------------------------------------
  test "ordinary blocker form edits retain direction and reject cycles" do
    first = @user.item_blocks.create!(blocker: @a, blocked: @b)
    @user.item_blocks.create!(blocker: @b, blocked: @c)
    ActionController::Base.allow_forgery_protection = false
    post login_url, params: { key: @user.access_key }
    patch item_block_url(first), params: { item_block: { blocker_id: @c.id, blocked_id: @b.id } }
    assert_response :unprocessable_entity
    assert_equal [@a.id, @b.id], first.reload.attributes.values_at("blocker_id", "blocked_id")
    patch item_block_url(first), params: { item_block: { blocker_id: @a.id, blocked_id: @d.id } }
    assert_redirected_to item_blocks_url
    get "/api/item_blocks/#{first.id}", headers: @authorization
    assert_response :success
    assert_equal [@a.id, @d.id], response.parsed_body["item_block"].values_at("blocker_id", "blocked_id")
  end

end
