require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:default_user)
    post login_url, params: { key: @user.access_key }
  end

  test "shows ready items and hides items with unfinished blockers" do
    category = categories(:default_category)
    mood = moods(:default_mood)

    ready = @user.items.create!(title: "Ready home item", category: category, mood: mood, done: false)
    completed_blocker = @user.items.create!(title: "Completed home blocker", category: category, mood: mood, done: true)
    blocked_by_completed = @user.items.create!(title: "Home item with completed blocker", category: category, mood: mood, done: false)
    blocked_by_completed.blockers << completed_blocker

    active_blocker = @user.items.create!(title: "Active home blocker", category: category, mood: mood, done: false)
    blocked_by_active = @user.items.create!(title: "Home item with active blocker", category: category, mood: mood, done: false)
    blocked_by_active.blockers << active_blocker

    get root_url, params: { per: 100 }

    assert_response :success
    assert_includes @response.body, ready.title
    assert_includes @response.body, blocked_by_completed.title
    assert_includes @response.body, active_blocker.title
    refute_includes @response.body, blocked_by_active.title
  end
end
