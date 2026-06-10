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

  test "hides items until they are within hide_days of deadline" do
    category = categories(:default_category)
    mood = moods(:default_mood)

    hidden_until_due_window = @user.items.create!(
      title: "Dog appointment",
      category: category,
      mood: mood,
      done: false,
      deadline: Date.current + 1.day,
      hide_days: 1
    )

    visible_in_due_window = @user.items.create!(
      title: "Weekly reminder",
      category: category,
      mood: mood,
      done: false,
      deadline: Date.current,
      hide_days: 1
    )

    get root_url, params: { per: 100 }

    assert_response :success
    refute_includes @response.body, hidden_until_due_window.title
    assert_includes @response.body, visible_in_due_window.title
  end
end
