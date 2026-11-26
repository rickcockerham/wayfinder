require "application_system_test_case"

class InventoryDestroyTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1200, 900]

  #-----------------------------------------------------------------------------
  setup do
    @user = users(:default_user)
    @shop = @user.shops.create!(name: "Delete button fixture supplier")
    @location = @user.locations.create!(name: "Delete button fixture bin")
    @stock = @user.inventory_items.create!(name: "Disposable delete button fixture", qty_have: 3, shop: @shop, location: @location)
    @other_stock = @user.inventory_items.create!(name: "Retained delete button fixture", qty_have: 1, shop: @shop, location: @location)
    @task = items(:one)
    @reservation = @task.item_inventories.create!(user: @user, inventory_item: @stock, qty_reserved: 1)
    visit login_url
    fill_in "key", with: @user.access_key
    click_on "Sign in"
    assert_current_path root_path
    visit inventory_items_url
    assert_selector "h1", text: "Inventory"
  end

  #-----------------------------------------------------------------------------
  def teardown
    # Close this disposable session before Capybara 3.40's Chrome-158 wildcard reset.
    Capybara.current_session.driver.quit
    super
  end

  #-----------------------------------------------------------------------------
  test "actual inventory destroy control confirms cancels and deletes only selected stock" do
    dismiss_confirm "Delete this inventory item?" do
      within("tr", text: @stock.name) { click_on "Destroy" }
    end
    assert_current_path inventory_items_path
    assert_text @stock.name
    assert InventoryItem.exists?(@stock.id)
    assert ItemInventory.exists?(@reservation.id)

    accept_confirm "Delete this inventory item?" do
      within("tr", text: @stock.name) { click_on "Destroy" }
    end
    assert_current_path inventory_items_path
    assert_no_text @stock.name
    assert_text @other_stock.name
    assert_not InventoryItem.exists?(@stock.id)
    # Preserve the existing model contract: remove joins, never the task or catalogs.
    assert_not ItemInventory.exists?(@reservation.id)
    assert Item.exists?(@task.id)
    assert Shop.exists?(@shop.id)
    assert Location.exists?(@location.id)
    assert InventoryItem.exists?(@other_stock.id)
  end
end
