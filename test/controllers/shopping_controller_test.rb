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
  # -----------------------------------------------------------------------------
  test "purchase respects the selected nested location without merging other stock" do
    shop = @user.shops.create!(name: "Supplier")
    root = @user.locations.create!(name: "Bins")
    left = @user.locations.create!(name: "left", parent: root)
    right = @user.locations.create!(name: "right", parent: root)
    wrong = @user.inventory_items.create!(name: "Cable", location: left, shop: shop, qty_have: 7)
    correct = @user.inventory_items.create!(name: "Cable", location: right, shop: shop, qty_have: 2)
    requirement = @user.material_requirements.create!(item: items(:one), shop: shop, name: "Cable", qty_needed: 3)
    post shopping_purchase_url, params: { shop_id: shop.id, location_id: right.id, purchase_ids: [requirement.id] }
    assert_response :redirect
    assert_equal 7, wrong.reload.qty_have
    assert_equal 5, correct.reload.qty_have
    assert_equal correct.id, items(:one).item_inventories.sole.inventory_item_id
    get inventory_items_url
    assert_includes response.body, "Bins → right"
    get new_inventory_item_url
    assert_includes response.body, "Bins → left"
  end

end
