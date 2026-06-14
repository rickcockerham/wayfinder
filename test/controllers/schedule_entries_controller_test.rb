require "test_helper"

class ScheduleEntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:default_user)
    post login_url, params: { key: @user.access_key }
    @user.create_importance_setting!(
      ImportanceSetting.default_attributes.merge(
        timezone: "Eastern Time (US & Canada)",
        planner_morning_start_minute: 360,
        planner_afternoon_start_minute: 780,
        planner_evening_start_minute: 1140
      )
    )
  end

  test "planner shows configured slot labels" do
    get planner_url

    assert_response :success
    assert_includes @response.body, "Morning (6:00 AM - 1:00 PM)"
    assert_includes @response.body, "Afternoon (1:00 PM - 7:00 PM)"
    assert_includes @response.body, "Evening (7:00 PM onward)"
  end
end
