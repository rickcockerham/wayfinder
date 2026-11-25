require "test_helper"

class UnknownInventoryQuantityTest < ActionDispatch::IntegrationTest
  # -----------------------------------------------------------------------------
  setup do
    @user = users(:default_user)
    @shop = @user.shops.create!(name: "Unknown quantity supplier")
    @location = @user.locations.create!(name: "Unknown quantity bin")
    @stock = @user.inventory_items.create!(name: "Unknown timers", shop: @shop, location: @location, unit: "each", qty_have: nil)
    @task = items(:one)
    post login_url, params: { key: @user.access_key }
  end

  # -----------------------------------------------------------------------------
  test "web shows unknown stock and explicit clear preserves known zero and blank-update semantics" do
    known = @user.inventory_items.create!(name: "Known timers", shop: @shop, qty_have: 7)
    zero = @user.inventory_items.create!(name: "Recorded zero", shop: @shop, qty_have: 0)
    get inventory_items_url
    assert_response :success
    assert_includes response.body, @stock.name
    assert_includes response.body, "Unknown"
    assert_not_includes response.body, zero.name
    get inventory_items_url, params: { zeros: 1 }
    assert_includes response.body, zero.name
    get inventory_item_url(@stock)
    assert_includes response.body, "Unknown"
    get edit_inventory_item_url(@stock)
    assert_select 'input[name="inventory_item[quantity_unknown]"][checked]'
    patch inventory_item_url(known), params: { inventory_item: { name: "Known renamed" } }
    assert_response :redirect
    assert_equal 7, known.reload.qty_have
    patch inventory_item_url(known), params: { inventory_item: { qty_have: "" } }
    assert_equal 7, known.reload.qty_have
    patch inventory_item_url(known), params: { inventory_item: { quantity_unknown: "1" } }
    assert_nil known.reload.qty_have
    patch inventory_item_url(known), params: { inventory_item: { qty_have: "0" } }
    assert_equal 0, known.reload.qty_have
    patch inventory_item_url(@stock), params: { inventory_item: { name: "Still unknown" } }
    assert_nil @stock.reload.qty_have
    # Ordinary legacy model/web creation still defaults to a recorded zero.
    defaulted = @user.inventory_items.create!(name: "Legacy default", shop: @shop)
    assert_equal 0, defaulted.qty_have
    other = User.create!(name: "Private unknown owner", access_key: "unknown-ui-test-only")
    private_stock = other.inventory_items.create!(name: "Private", shop: other.shops.create!(name: "Private"), qty_have: 9)
    patch inventory_item_url(private_stock), params: { inventory_item: { quantity_unknown: "1" } }
    assert_response :not_found
    assert_equal 9, private_stock.reload.qty_have
  end

  # -----------------------------------------------------------------------------
  test "completion consumes reservations without fabricating a balance or a deficit for unknown stock" do
    known = @user.inventory_items.create!(name: "Known stock", shop: @shop, qty_have: 5)
    @task.item_inventories.create!(user: @user, inventory_item: @stock, qty_reserved: 2)
    @task.item_inventories.create!(user: @user, inventory_item: known, qty_reserved: 2)
    result = ItemCompletion.new(@task).consume!
    assert_nil @stock.reload.qty_have
    assert_equal 3, known.reload.qty_have
    assert_equal 2, result.consumed_lines
    assert_empty @task.item_inventories.reload
    assert_equal true, result.deficits.sole[:quantity_unknown]
    assert_nil result.deficits.sole[:shortage]
  end

  # -----------------------------------------------------------------------------
  test "shopping adds reservations while retaining unknown starting quantity" do
    requirement = @user.material_requirements.create!(item: @task, shop: @shop, name: @stock.name, unit: "each", qty_needed: 3)
    post shopping_purchase_url, params: { shop_id: @shop.id, location_id: @location.id, purchase_ids: [requirement.id] }
    assert_response :redirect
    assert_nil @stock.reload.qty_have
    assert_equal 3, @task.item_inventories.sole.qty_reserved
    assert_not MaterialRequirement.exists?(requirement.id)
  end

  # -----------------------------------------------------------------------------
  test "readiness and shopping advice disclose unknown portions across locations" do
    @user.material_requirements.create!(item: @task, shop: @shop, name: @stock.name, unit: "each", qty_needed: 6)
    second = @user.locations.create!(name: "Second bin")
    known = @user.inventory_items.create!(name: @stock.name, shop: @shop, location: second, unit: "each", qty_have: 2)
    inventory = @user.inventory_items.group_by { |row| row.name.downcase }
    missing = @task.missing_materials_by(inventory).sole
    assert_equal true, missing[:quantity_unknown]
    assert_nil missing[:short]
    assert_not @task.ready_now?(inventory_hash: inventory)
    get root_url, params: { shop_id: @shop.id, per: 100 }
    assert_response :success
    assert_includes response.body, "quantity unknown"
    assert_includes response.body, "recount needed"
    get items_url
    assert_response :success
    assert_includes response.body, "quantity unknown"
    get materials_item_url(@task)
    assert_response :success
    assert_includes response.body, "Unknown"
    # Once both counts are known, same-unit quantities add across actual locations.
    @stock.update!(qty_have: 3)
    inventory = @user.inventory_items.group_by { |row| row.name.downcase }
    assert_equal 1, @task.missing_materials_by(inventory).sole[:short]
    known.update!(qty_have: 4)
    inventory = @user.inventory_items.group_by { |row| row.name.downcase }
    assert_empty @task.missing_materials_by(inventory)
    assert @task.ready_now?(inventory_hash: inventory)
  end
end
