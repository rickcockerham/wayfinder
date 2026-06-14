require "test_helper"

class ItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:default_user)
    @item = items(:one)
    post login_url, params: { key: @user.access_key }
  end

  test "should get index" do
    get items_url
    assert_response :success
  end

  test "should get new" do
    get new_item_url
    assert_response :success
  end

  test "new item form excludes hidden categories and moods" do
    visible_category = @user.categories.create!(name: "Visible category")
    hidden_category = @user.categories.create!(name: "Hidden category", hidden: true)
    visible_mood = @user.moods.create!(name: "Visible mood")
    hidden_mood = @user.moods.create!(name: "Hidden mood", hidden: true)

    get new_item_url

    assert_response :success
    assert_includes @response.body, visible_category.name
    assert_not_includes @response.body, hidden_category.name
    assert_includes @response.body, visible_mood.name
    assert_not_includes @response.body, hidden_mood.name
  end

  test "materials form excludes hidden shops" do
    visible_shop = @user.shops.create!(name: "Visible shop")
    hidden_shop = @user.shops.create!(name: "Hidden shop", hidden: true)

    get materials_item_url(@item)

    assert_response :success
    assert_includes @response.body, visible_shop.name
    assert_not_includes @response.body, hidden_shop.name
  end

  test "should create item" do
    assert_difference("Item.count") do
      post items_url, params: {
        item: {
          title: "Created item",
          category_id: categories(:default_category).id,
          mood_id: moods(:default_mood).id
        }
      }
    end

    assert_redirected_to items_url
    assert_equal @user, Item.last.user
  end

  test "should show item" do
    get item_url(@item)
    assert_response :success
    assert_select "input[type='range'][name='item[personal_impact]'][min='0'][max='5'][step='1']"
    assert_select "input[type='range'][name='item[emotional_impact]'][min='0'][max='5'][step='1']"
    assert_select "input[type='range'][name='item[family_impact]'][min='0'][max='5'][step='1']"
  end

  test "show labels non-recurring date as deadline" do
    @item.update!(deadline: Date.new(2026, 9, 1), recurrence_kind: :no_recurrence)

    get item_url(@item)

    assert_response :success
    assert_includes @response.body, "<strong>Deadline:</strong> 2026-09-01"
    assert_not_includes @response.body, "<strong>Next Date:</strong>"
    assert_not_includes @response.body, "<strong>Schedule:</strong>"
  end

  test "show labels recurring date and schedule" do
    @item.update!(
      deadline: Date.new(2026, 9, 1),
      recurrence_kind: :fixed_schedule,
      recurrence_unit: :week,
      recurrence_interval: 1
    )

    get item_url(@item)

    assert_response :success
    assert_includes @response.body, "<strong>Next Date:</strong> 2026-09-01"
    assert_includes @response.body, "<strong>Schedule:</strong> Every 1 week."
    assert_not_includes @response.body, "<strong>Deadline:</strong>"
  end

  test "should get edit" do
    get edit_item_url(@item)
    assert_response :success
    assert_select "input[name='item[deadline]']"
    assert_select "input[name='item[recurrence_start_on]']", count: 0
  end

  test "should update item" do
    patch item_url(@item), params: { item: { title: "Updated item" } }
    assert_redirected_to item_url(@item)
  end

  test "completing a recurring item advances the same item instead of marking it done" do
    @item.update!(
      deadline: Date.new(2026, 6, 9),
      recurrence_kind: :fixed_schedule,
      recurrence_unit: :week,
      recurrence_interval: 2
    )

    assert_no_difference("Item.count") do
      patch item_url(@item), params: { item: { done: "1" } }
    end

    assert_redirected_to root_url

    @item.reload
    assert_not @item.done?
    assert_nil @item.completed_at
    assert_equal Date.new(2026, 6, 23), @item.deadline
  end

  test "should destroy item" do
    assert_difference("Item.count", -1) do
      delete item_url(@item)
    end

    assert_redirected_to items_url
  end
end
