require "test_helper"
require "minitest/mock"
require "json"
require "net/http"
require "tmpdir"

class ItemPrioritiesApiTest < ActionDispatch::IntegrationTest
  # --------------------------------------------------------------------------
  setup do
    @saved_env = %w[WAYFINDER_API_TOKEN_SHA256 WAYFINDER_API_USER_ID WAYFINDER_API_CONFIG].to_h { |key| [key, ENV[key]] }
    @user = User.create!(name: "Priorities fixture", access_key: "priorities-fixture-only")
    @category = @user.categories.create!(name: "Work")
    @mood = @user.moods.create!(name: "Desk")
    @token = "b" * 64
    ENV["WAYFINDER_API_TOKEN_SHA256"] = Digest::SHA256.hexdigest(@token)
    ENV["WAYFINDER_API_USER_ID"] = @user.id.to_s
    @headers = { "Authorization" => "Bearer #{@token}" }
    @make = ->(title, **attributes) { @user.items.create!({ title: title, category: @category, mood: @mood }.merge(attributes)) }
  end

  # --------------------------------------------------------------------------
  teardown do
    @saved_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  # --------------------------------------------------------------------------
  test "priorities uses owner weights returns five and excludes ineligible items" do
    travel_to Time.utc(2026, 11, 25, 16) do
      @user.create_importance_setting!(ImportanceSetting.default_attributes.merge(personal_weight: 20, emotional_weight: 0))
      eligible = (1..6).map { |n| @make.call("Priority #{n}", personal_impact: n - 1) }
      @make.call("Done", done: true, personal_impact: 99)
      @make.call("At hide boundary", deadline: Date.current + 3, hide_days: 3, personal_impact: 99)
      visible = @make.call("Inside hide window", deadline: Date.current + 2, hide_days: 3, personal_impact: 0)
      blocked = @make.call("Unfinished blocker", personal_impact: 99)
      blocker = @make.call("Blocker", done: false)
      ItemBlock.create!(user: @user, blocker: blocker, blocked: blocked)
      finished = @make.call("Finished blocker", done: true)
      cleared = @make.call("Cleared dependency", personal_impact: 5, deadline: Date.current - 1)
      ItemBlock.create!(user: @user, blocker: finished, blocked: cleared)
      get "/api/items/priorities", headers: @headers
      assert_response :success
      rows = response.parsed_body["items"]
      assert_equal [cleared.id, *eligible.reverse.first(4).map(&:id)], rows.map { |row| row["id"] }
      assert rows.each_cons(2).all? { |a, b| a["importance_score"] >= b["importance_score"] }
      assert_equal Time.current.utc.iso8601, response.parsed_body["observed_at"]
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_nil response.headers["X-CSRF-Token"]
      assert_equal "/items/#{cleared.id}", URI(rows.first["url"]).path
      assert_not_includes rows.map { |row| row["id"] }, visible.id
    end
  end

  # --------------------------------------------------------------------------
  test "fresh planner defaults and explicit filters reuse home normalization" do
    travel_to Time.utc(2026, 11, 25, 16) do
      @user.create_importance_setting!(ImportanceSetting.default_attributes)
      planned_category = @user.categories.create!(name: "Planned")
      other_mood = @user.moods.create!(name: "Outside")
      ScheduleEntry.create!(user: @user, category: planned_category, on_date: Date.current, day_part: :morning)
      planned = @make.call("Planned task", category: planned_category)
      explicit = @make.call("Explicit task", mood: other_mood, time_scale: 1)
      @make.call("Too long", mood: other_mood, time_scale: 2)
      @make.call("Different mood", time_scale: 1)
      get "/api/items/priorities", headers: @headers
      assert_equal [planned.id], response.parsed_body["items"].map { |row| row["id"] }
      assert_equal planned_category.id, response.parsed_body.dig("filters", "category_id")
      get "/api/items/priorities", params: { category_id: @category.id, mood_ids: [other_mood.id], time_i: 1 }, headers: @headers
      assert_equal [explicit.id], response.parsed_body["items"].map { |row| row["id"] }
      assert_equal [other_mood.id], response.parsed_body.dig("filters", "mood_ids")
      assert_equal 1, response.parsed_body.dig("filters", "time_i")
    end
  end

  # --------------------------------------------------------------------------
  test "no domain writes hidden moods and other owners are excluded" do
    hidden = @user.moods.create!(name: "Hidden", hidden: true)
    @make.call("Hidden mood", mood: hidden)
    visible = @make.call("Visible")
    # Existing default-user fixture must never appear for this bearer owner.
    assert_no_difference("ImportanceSetting.count") do
      assert_no_difference("Item.count") do
        get "/api/items/priorities", headers: @headers
      end
    end
    assert_response :success
    assert_equal [visible.id], response.parsed_body["items"].map { |row| row["id"] }
    assert_equal 7, response.parsed_body.dig("filters", "time_i")
    assert_equal "importance", response.parsed_body.dig("filters", "sort")
    get "/api/items/priorities", params: { q: "Hidden" }, headers: @headers
    assert_response :bad_request
    assert_no_difference("Item.count") do
      post "/api/items/priorities", headers: @headers
      assert_response :not_found
    end
    get "/api/items/priorities", headers: { "Authorization" => "Bearer wrong" }
    assert_response :unauthorized
    get "/api/items/priorities"
    assert_response :unauthorized
  end

  # --------------------------------------------------------------------------
  test "ties and time sorting have the same order as shared home selection" do
    6.times { |n| @make.call("Equal #{n}", time_scale: 1) }
    filters = { q: "", mood_ids: [@mood.id], category_id: nil, time_i: 7, sort: "importance" }
    expected = HomeItemSelection.new(@user, filters).call.first(5).map(&:id)
    get "/api/items/priorities", headers: @headers
    assert_equal expected, response.parsed_body["items"].map { |row| row["id"] }
    quick = @make.call("Quick", time_scale: 0)
    get "/api/items/priorities", params: { sort: "time" }, headers: @headers
    assert_equal quick.id, response.parsed_body["items"].first["id"]
    assert_equal "time", response.parsed_body.dig("filters", "sort")
    # The generic CRUD collection retains its ID order and pagination contract.
    get "/api/items", params: { limit: 1 }, headers: @headers
    assert_equal @user.items.minimum(:id), response.parsed_body["items"].first["id"]
  end

  # --------------------------------------------------------------------------
  test "CLI entry point reaches real priorities route with synthetic credential" do
    tasks = (1..25).map { |n| @make.call("CLI priority #{n}", deadline: Date.current - n) }
    Dir.mktmpdir("priorities-client-") do |directory|
      path = File.join(directory, "api.json")
      File.write(path, JSON.generate(token: @token), perm: 0o600)
      ENV["WAYFINDER_API_CONFIG"] = path
      saved_argv = ARGV.dup
      http = Net::HTTP.new("example.invalid", 443)
      requests = 0
      http.stub(:request, ->(request) {
        requests += 1
        get request.path, headers: { "Authorization" => request["Authorization"] }
        result_class = response.successful? ? Net::HTTPOK : Net::HTTPBadRequest
        result = result_class.new("1.1", response.status.to_s, "Fixture")
        result.body = response.body
        result.instance_variable_set(:@read, true)
        result
      }) do
        Net::HTTP.stub(:new, http) do
          [["/api/items/priorities", 5], ["/api/items/priorities?limit=20", 20]].each do |endpoint, count|
            ARGV.replace(["get", endpoint])
            output, errors = capture_io { load Rails.root.join("bin/wayfinder-api") }
            assert_empty errors
            assert_equal tasks.reverse.first(count).map(&:id), JSON.parse(output)["items"].map { |row| row["id"] }
            assert_not_includes output, @token
          end
          ARGV.replace(["get", "/api/items/priorities?limit=0"])
          output, errors = capture_io do
            assert_raises(SystemExit) { load Rails.root.join("bin/wayfinder-api") }
          end
          assert_equal "invalid_limit", JSON.parse(output)["error"]
          assert_includes errors, "HTTP 400"
        end
      end
      assert_equal 3, requests
      assert_response :bad_request
    ensure
      ARGV.replace(saved_argv) if saved_argv
    end
  end
  # --------------------------------------------------------------------------
  test "browser saved filters are neither inherited nor overwritten" do
    second = @user.categories.create!(name: "Other category")
    first_task = @make.call("Default candidate")
    second_task = @make.call("Saved browser candidate", category: second, personal_impact: 5)
    post login_url, params: { key: @user.access_key }
    get root_url, params: { category_id: second.id, time_i: 1 }
    assert_response :success
    get "/api/items/priorities"
    assert_response :success
    assert_nil response.parsed_body.dig("filters", "category_id")
    assert_equal 7, response.parsed_body.dig("filters", "time_i")
    assert_equal [second_task.id, first_task.id], response.parsed_body["items"].map { |row| row["id"] }
    # Inspect only the synthetic test session; no live browser or data is used.
    assert_equal second.id, session[:filters_v2]["value"].with_indifferent_access[:category_id]
    get "/api/items/priorities", params: { category_id: [second.id] }, headers: @headers
    assert_response :bad_request
  end
  # --------------------------------------------------------------------------
  test "ranked limit defaults to five accepts twenty and validates bounds without bypassing eligibility" do
    tasks = (1..25).map { |n| @make.call("Ranked #{n}", deadline: Date.current - n) }
    @make.call("Completed", done: true, personal_impact: 99)
    blocker = @make.call("Hidden unfinished blocker", deadline: Date.current + 10, hide_days: 1, personal_impact: 99)
    blocked = @make.call("Blocked", personal_impact: 99)
    ItemBlock.create!(user: @user, blocker: blocker, blocked: blocked)
    [[{}, 5], [{ limit: 20 }, 20], [{ limit: 1 }, 1], [{ limit: 100 }, 25], [{ per: 100 }, 5]].each do |query, count|
      get "/api/items/priorities", params: query, headers: @headers
      assert_response :success
      assert_equal tasks.reverse.first(count).map(&:id), response.parsed_body["items"].map { |row| row["id"] }
      assert_equal query.fetch(:limit, 5), response.parsed_body.dig("filters", "per")
    end
    [0, -1, 101, "", "abc", "1.5", [20], { count: 20 }].each do |limit|
      get "/api/items/priorities", params: { limit: limit }, headers: @headers
      assert_response :bad_request, limit.inspect
      assert_equal "invalid_limit", response.parsed_body["error"]
    end
  end
end
