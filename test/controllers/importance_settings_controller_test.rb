require "test_helper"

class ImportanceSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:default_user)
    post login_url, params: { key: @user.access_key }
  end

  test "shows scoring settings page with explanations" do
    get importance_setting_url

    assert_response :success
    assert_includes @response.body, "Importance Settings"
    assert_includes @response.body, "How strongly the personal impact slider contributes to the score."
    assert_includes @response.body, "The maximum urgency boost an item gets as it reaches its deadline day."
    assert_includes @response.body, "Planner Settings"
    assert_includes @response.body, "The timezone used to decide which planner time slot is active right now."
  end

  test "updates scoring settings" do
    patch importance_setting_url, params: {
      importance_setting: {
        personal_weight: 4.5,
        quick_task_bonus: 2.5,
        timezone: "Eastern Time (US & Canada)",
        planner_morning_start_time: "06:00",
        planner_afternoon_start_time: "13:00",
        planner_evening_start_time: "19:00"
      }
    }

    assert_redirected_to importance_setting_url
    assert_equal 4.5, @user.reload.importance_setting.personal_weight
    assert_equal 2.5, @user.importance_setting.quick_task_bonus
    assert_equal "Eastern Time (US & Canada)", @user.importance_setting.timezone
    assert_equal 360, @user.importance_setting.planner_morning_start_minute
  end
end
