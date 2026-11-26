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
  #-----------------------------------------------------------------------------
  test "inventory destroy is a confirmed form with native DELETE and CSRF fields" do
    stock = @user.inventory_items.create!(name: "Destroy form fixture", shop: @user.shops.create!(name: "Destroy form supplier"), qty_have: 1)
    get inventory_items_url
    assert_response :success
    assert_select "form[action='#{inventory_item_path(stock)}'][method='post'][data-turbo='false']" do
      assert_select "input[name='_method'][value='delete']"
      assert_select "button[type='submit']", text: "Destroy"
    end
    assert_select "form[action='#{inventory_item_path(stock)}'][onsubmit*='confirm']"
    assert_select "a[href='#{inventory_item_path(stock)}'][data-method='delete']", count: 0
  end

  #-----------------------------------------------------------------------------
  test "delete retains owner isolation and existing reservation cascade without deleting tasks or locations" do
    shop = @user.shops.create!(name: "Delete behavior supplier")
    location = @user.locations.create!(name: "Delete behavior bin")
    stock = @user.inventory_items.create!(name: "Deletable stock fixture", shop: shop, location: location, qty_have: 3)
    task = items(:one)
    reservation = task.item_inventories.create!(user: @user, inventory_item: stock, qty_reserved: 1)
    other = User.create!(name: "Other delete fixture", access_key: "delete-other-test-only")
    private_stock = other.inventory_items.create!(name: "Private stock fixture", shop: other.shops.create!(name: "Private supplier"))
    get inventory_item_url(stock)
    assert_response :success
    assert InventoryItem.exists?(stock.id)
    assert_no_difference(["InventoryItem.count", "ItemInventory.count"]) do
      delete inventory_item_url(private_stock)
      assert_response :not_found
    end
    assert_difference("InventoryItem.count", -1) do
      assert_difference("ItemInventory.count", -1) do
        assert_no_difference(["Item.count", "Location.count", "Shop.count"]) do
          delete inventory_item_url(stock)
          assert_redirected_to inventory_items_url
        end
      end
    end
    assert_not ItemInventory.exists?(reservation.id)
    assert InventoryItem.exists?(private_stock.id)
    delete logout_url
    assert_no_difference("InventoryItem.count") do
      delete inventory_item_url(private_stock)
      assert_redirected_to login_url
    end
  end

  #-----------------------------------------------------------------------------
  test "inventory delete requires a valid session CSRF token when protection is enabled" do
    stock = @user.inventory_items.create!(name: "CSRF delete fixture", shop: @user.shops.create!(name: "CSRF supplier"), qty_have: 1)
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    assert_no_difference("InventoryItem.count") do
      delete inventory_item_url(stock)
      assert_response :unprocessable_entity
    end
    get inventory_items_url
    form = Nokogiri::HTML(response.body).at_css("form[action='#{inventory_item_path(stock)}']")
    token = form.at_css("input[name='authenticity_token']")["value"]
    assert_difference("InventoryItem.count", -1) do
      delete inventory_item_url(stock), params: { authenticity_token: token }
      assert_redirected_to inventory_items_url
    end
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

end
