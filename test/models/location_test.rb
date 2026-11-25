require "test_helper"

class LocationTest < ActiveSupport::TestCase
  # -----------------------------------------------------------------------------
  test "siblings are unique while contextual names can repeat" do
    user = users(:default_user)
    bins = user.locations.create!(name: "Electronics bins")
    drawers = user.locations.create!(name: "Electronics Drawers")
    row = user.locations.create!(name: "middle", parent: bins)
    other = user.locations.create!(name: "middle", parent: drawers)
    assert_equal [bins.id, row.id], row.path.map { |node| node[:id] }
    assert_equal "Electronics Drawers → middle", other.full_name
    assert_not user.locations.new(name: "MIDDLE", parent: bins).valid?
    assert_not user.locations.new(name: "ELECTRONICS BINS").valid?
    # Database indexes, including null-parent roots, protect against concurrent writers.
    assert_raises(ActiveRecord::RecordNotUnique) { user.locations.new(name: bins.name).save!(validate: false) }
    assert_raises(ActiveRecord::RecordNotUnique) { user.locations.new(name: row.name, parent: bins).save!(validate: false) }
  end

  # -----------------------------------------------------------------------------
  test "ownership immutable ancestry and restrictive deletion protect the tree" do
    user = users(:default_user)
    root = user.locations.create!(name: "Root")
    child = user.locations.create!(name: "Child", parent: root)
    other = User.create!(name: "Other", access_key: "location-tests-only")
    assert_not other.locations.new(name: "Cross owner", parent: root).valid?
    assert_not root.update(parent: child)
    assert_not child.update(parent: nil)
    child.reload
    assert_not child.update(user: other)
    assert_raises(ActiveRecord::DeleteRestrictionError) { root.reload.destroy! }
    shop = user.shops.create!(name: "Shop")
    user.inventory_items.create!(name: "Stock", location: child.reload, shop: shop)
    assert_raises(ActiveRecord::DeleteRestrictionError) { child.destroy! }
    assert_equal root.id, child.reload.parent_id
  end

  # -----------------------------------------------------------------------------
  test "deep paths are iterative and corrupted ancestry fails closed" do
    user = users(:default_user)
    leaf = user.locations.create!(name: "Root")
    35.times { |i| leaf = user.locations.create!(name: "Level #{i}", parent: leaf) }
    assert_equal 36, leaf.path.length
    leaf.update_column(:parent_id, leaf.id)
    assert_raises(ActiveRecord::RecordInvalid) { leaf.reload.path }
  end
end
