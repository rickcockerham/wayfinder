require "test_helper"

class ShoppingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:default_user)
    post login_url, params: { key: @user.access_key }
  end

  test "shopping filters exclude hidden shops and locations" do
    visible_shop = @user.shops.create!(name: "Visible shop")
    hidden_shop = @user.shops.create!(name: "Hidden shop", hidden: true)
    visible_location = @user.locations.create!(name: "Visible location")
    hidden_location = @user.locations.create!(name: "Hidden location", hidden: true)
    item = @user.items.create!(
      title: "Shopping item",
      category: categories(:default_category),
      mood: moods(:default_mood)
    )
    @user.material_requirements.create!(
      item: item,
      shop: visible_shop,
      name: "Milk",
      qty_needed: 1
    )

    get shopping_url

    assert_response :success
    assert_includes @response.body, visible_shop.name
    assert_not_includes @response.body, hidden_shop.name
    assert_includes @response.body, visible_location.name
    assert_not_includes @response.body, hidden_location.name
  end
end
