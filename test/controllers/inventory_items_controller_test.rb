require "test_helper"

class InventoryItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:default_user)
    post login_url, params: { key: @user.access_key }
  end

  test "new inventory item form excludes hidden locations and shops" do
    visible_location = @user.locations.create!(name: "Visible location")
    hidden_location = @user.locations.create!(name: "Hidden location", hidden: true)
    visible_shop = @user.shops.create!(name: "Visible shop")
    hidden_shop = @user.shops.create!(name: "Hidden shop", hidden: true)

    get new_inventory_item_url

    assert_response :success
    assert_includes @response.body, visible_location.name
    assert_not_includes @response.body, hidden_location.name
    assert_includes @response.body, visible_shop.name
    assert_not_includes @response.body, hidden_shop.name
  end
end
