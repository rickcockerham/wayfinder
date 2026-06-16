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

  test "shows deadline items when hide_days is zero" do
    category = categories(:default_category)
    mood = moods(:default_mood)

    visible_deadline = @user.items.create!(
      title: "Future deadline on home",
      category: category,
      mood: mood,
      done: false,
      deadline: Date.current + 30.days,
      hide_days: 0
    )

    get root_url, params: { per: 100 }

    assert_response :success
    assert_includes @response.body, visible_deadline.title
  end

  test "searches item titles and notes" do
    category = categories(:default_category)
    mood = moods(:default_mood)

    title_match = @user.items.create!(title: "Dog appointment", notes: "plain note", category: category, mood: mood, done: false)
    notes_match = @user.items.create!(title: "Vet task", notes: "Discuss dog meds", category: category, mood: mood, done: false)
    non_match = @user.items.create!(title: "Groceries", notes: "Milk and eggs", category: category, mood: mood, done: false)

    get root_url, params: { per: 100, q: "dog" }

    assert_response :success
    assert_includes @response.body, title_match.title
    assert_includes @response.body, notes_match.title
    refute_includes @response.body, non_match.title
  end

  test "search overrides done hide_days and blocked filters" do
    category = categories(:default_category)
    mood = moods(:default_mood)

    done_match = @user.items.create!(
      title: "Archived dog task",
      notes: "done item",
      category: category,
      mood: mood,
      done: true
    )

    hidden_match = @user.items.create!(
      title: "Hidden dog appointment",
      notes: "future hidden item",
      category: category,
      mood: mood,
      done: false,
      deadline: Date.current + 10.days,
      hide_days: 1
    )

    blocker = @user.items.create!(
      title: "Dog blocker",
      category: category,
      mood: mood,
      done: false
    )
    blocked_match = @user.items.create!(
      title: "Blocked dog task",
      notes: "blocked item",
      category: category,
      mood: mood,
      done: false
    )
    blocked_match.blockers << blocker

    get root_url, params: { per: 100, q: "dog" }

    assert_response :success
    assert_includes @response.body, done_match.title
    assert_includes @response.body, hidden_match.title
    assert_includes @response.body, blocked_match.title
  end

  test "renders time commitment slider with current label" do
    get root_url

    assert_response :success
    assert_select "input[type='range'][name='time_i'][min='0'][max='7'][step='1']"
    assert_includes @response.body, "id=\"time_i_label\""
  end

  test "renders mood filters as toggle buttons" do
    get root_url

    assert_response :success
    assert_select "button[data-filter-chip]", minimum: 1
    assert_select "input.filter-chip-input[type='checkbox'][name='mood_ids[]']", minimum: 1
  end

  test "mobile item cards expose mood time and deadline or schedule fields" do
    recurring = @user.items.create!(
      title: "Weekly reminder",
      category: categories(:default_category),
      mood: moods(:default_mood),
      recurrence_kind: :fixed_schedule,
      recurrence_unit: :week,
      recurrence_interval: 1,
      deadline: Date.current,
      hide_days: 1,
      personal_impact: 5,
      time_scale: 2
    )

    get root_url, params: { per: 100 }

    assert_response :success
    assert_includes @response.body, recurring.title
    assert_includes @response.body, 'data-label="Mood"'
    assert_includes @response.body, 'data-label="Time"'
    assert_includes @response.body, 'data-label="Schedule"'
    assert_includes @response.body, recurring.recurrence_schedule_description
  end

  test "home filters exclude hidden categories and moods" do
    visible_category = @user.categories.create!(name: "Visible category")
    hidden_category = @user.categories.create!(name: "Hidden category", hidden: true)
    visible_mood = @user.moods.create!(name: "Visible mood")
    hidden_mood = @user.moods.create!(name: "Hidden mood", hidden: true)

    get root_url

    assert_response :success
    assert_includes @response.body, visible_category.name
    assert_not_includes @response.body, hidden_category.name
    assert_includes @response.body, visible_mood.name
    assert_not_includes @response.body, hidden_mood.name
  end
end
