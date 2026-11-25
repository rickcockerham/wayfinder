require "test_helper"

class LocationsControllerTest < ActionDispatch::IntegrationTest
  #-----------------------------------------------------------------------------
  setup do
    # Use ordinary browser authentication and separate owners for every request.
    @user = users(:default_user)
    @root = @user.locations.create!(name: "Workshop annex")
    @other = User.create!(name: "Private location owner", access_key: "location-web-private-fixture")
    @foreign = @other.locations.create!(name: "Private storage wing")
    post login_url, params: { key: @user.access_key }
  end

  #-----------------------------------------------------------------------------
  test "browser creates arbitrary depth locations with their complete ancestry" do
    parent = @root
    names = [@root.name]
    ids = [@root.id]
    segments = ["Tall cabinet", "Lower rack", "Tray C", "Rear pocket", "Packet 7"]

    # Each existing location can become the parent of another level.
    assert_difference("Location.count", segments.length) do
      segments.each do |name|
        post locations_url, params: { location: { name: name, parent_id: parent.id } }
        assert_redirected_to locations_url
        parent = @user.locations.find_by!(name: name, parent_id: parent.id)
        names << name
        ids << parent.id

        # Capture both names and identities so an accidental flat tree fails.
        assert_equal names, parent.path.map { |node| node[:name] }
        assert_equal ids, parent.path.map { |node| node[:id] }
        assert_equal names.join(" → "), parent.full_name
        assert_equal @user.id, parent.user_id
      end
    end
  end

  #-----------------------------------------------------------------------------
  test "identical names are allowed under different parents but not within one parent" do
    alternate = @user.locations.create!(name: "Supply alcove")

    # Repeated physical labels remain distinct when their ancestry differs.
    assert_difference("Location.count", 2) do
      [@root, alternate].each do |parent|
        post locations_url, params: { location: { name: "Drawer Q", parent_id: parent.id } }
        assert_redirected_to locations_url
      end
    end
    first = @user.locations.find_by!(name: "Drawer Q", parent: @root)
    second = @user.locations.find_by!(name: "Drawer Q", parent: alternate)
    assert_not_equal first.id, second.id
    assert_not_equal first.full_name, second.full_name

    # The invalid submission keeps the selected branch visible for correction.
    assert_no_difference("Location.count") do
      post locations_url, params: { location: { name: "Drawer Q", parent_id: @root.id } }
      assert_response :unprocessable_entity
    end
    assert_select 'select[name="location[parent_id]"] option[selected][value=?]', @root.id.to_s
    assert_includes response.body, "has already been taken"
  end

  #-----------------------------------------------------------------------------
  test "invalid nested location names render errors without writing records" do
    # Both model validation failures retain the parent instead of creating roots.
    ["", "x" * 256].each do |name|
      assert_no_difference("Location.count") do
        post locations_url, params: { location: { name: name, parent_id: @root.id } }
        assert_response :unprocessable_entity
      end
      assert_select 'select[name="location[parent_id]"] option[selected][value=?]', @root.id.to_s
      assert_select 'input[name="location[name]"]'
    end
  end

  #-----------------------------------------------------------------------------
  test "foreign and nonexistent parents are rejected before rendering or creating" do
    missing_id = Location.maximum(:id) + 10_000

    # A direct child-creation URL must have the same owner checks as a POST.
    [@foreign.id, missing_id].each do |parent_id|
      get new_location_url, params: { parent_id: parent_id }
      assert_response :not_found

      assert_no_difference("Location.count") do
        post locations_url, params: { location: { name: "Rejected drawer", parent_id: parent_id } }
        assert_response :not_found
      end
    end
    assert_equal @other.id, @foreign.reload.user_id
  end

  #-----------------------------------------------------------------------------
  test "new form uses complete owner scoped parent paths and retains an explicitly selected hidden parent" do
    child = @user.locations.create!(name: "Drawer M", parent: @root)
    leaf = @user.locations.create!(name: "Pocket R", parent: child)
    hidden = @user.locations.create!(name: "Hidden cabinet", hidden: true, parent: @root)

    # Full paths disambiguate repeated short names in the parent chooser.
    get new_location_url, params: { parent_id: leaf.id }
    assert_response :success
    assert_select 'select[name="location[parent_id]"]' do
      assert_select 'option[value=?]', @root.id.to_s, text: @root.full_name
      assert_select 'option[value=?]', child.id.to_s, text: child.full_name
      assert_select 'option[selected][value=?]', leaf.id.to_s, text: leaf.full_name
      assert_select 'option[value=""]'
      assert_select 'option[value=?]', hidden.id.to_s, count: 0
      assert_select 'option[value=?]', @foreign.id.to_s, count: 0
    end

    # Following an owned hidden parent's child link preserves that explicit choice.
    get new_location_url, params: { parent_id: hidden.id }
    assert_response :success
    assert_select 'select[name="location[parent_id]"] option[selected][value=?]', hidden.id.to_s, text: hidden.full_name
    assert_not_includes response.body, @foreign.name
  end

  #-----------------------------------------------------------------------------
  test "location pages browse ancestry and offer child creation at each level" do
    child = @user.locations.create!(name: "Drawer M", parent: @root)
    leaf = @user.locations.create!(name: "Pocket R", parent: child)

    # The index exposes stable detail and child-creation URLs for deep locations.
    get locations_url
    assert_response :success
    assert_select 'a[href=?]', location_path(leaf), text: leaf.full_name
    [@root, child, leaf].each do |location|
      assert_select 'a[href=?]', new_location_path(parent_id: location.id)
    end
    assert_not_includes response.body, @foreign.name

    # A middle-level detail page links both ancestors and its direct descendants.
    get location_url(child)
    assert_response :success
    assert_includes response.body, child.full_name
    assert_select 'a[href=?]', location_path(@root), text: @root.name
    assert_select 'a[href=?]', location_path(leaf)
    assert_select 'a[href=?]', new_location_path(parent_id: child.id)
    assert_not_includes response.body, @foreign.name

    get location_url(leaf)
    assert_response :success
    assert_select 'form[onsubmit*="confirm"] input[name="_method"][value="delete"]'
    [@root, child].each do |ancestor|
      assert_select 'a[href=?]', location_path(ancestor), text: ancestor.name
    end
    assert_select 'a[href=?]', new_location_path(parent_id: leaf.id)
  end

  #-----------------------------------------------------------------------------
  test "edits show fixed ancestry and reject crafted attempts to change parents" do
    child = @user.locations.create!(name: "Drawer M", parent: @root)
    leaf = @user.locations.create!(name: "Pocket R", parent: child)
    alternate = @user.locations.create!(name: "Supply alcove")

    # Existing ancestry is readable without presenting a misleading move control.
    get edit_location_url(leaf)
    assert_response :success
    assert_select 'select[name="location[parent_id]"]', count: 0
    assert_includes response.body, child.full_name

    # Failed reparenting must not commit the simultaneous name change either.
    patch location_url(leaf), params: { location: { name: "Rejected rename", parent_id: alternate.id } }
    assert_response :unprocessable_entity
    assert_equal child.id, leaf.reload.parent_id
    assert_equal "Pocket R", leaf.name
    assert_includes response.body, "cannot change after creation"

    # Supplying the unchanged parent still allows ordinary nested-location edits.
    patch location_url(leaf), params: { location: { name: "Pocket S", parent_id: child.id } }
    assert_redirected_to locations_url
    assert_equal child.id, leaf.reload.parent_id
    assert_equal "Pocket S", leaf.name
  end

  #-----------------------------------------------------------------------------
  test "root creation and renaming continue without a parent" do
    # Leaving the parent blank keeps the original standalone-location workflow.
    get new_location_url
    assert_response :success
    assert_select 'select[name="location[parent_id]"] option[value=""]'
    assert_difference("Location.count", 1) do
      post locations_url, params: { location: { name: "Standalone cupboard", parent_id: "" } }
      assert_redirected_to locations_url
    end
    location = @user.locations.find_by!(name: "Standalone cupboard")
    assert_nil location.parent_id

    patch location_url(location), params: { location: { name: "Renamed cupboard", hidden: "1" } }
    assert_redirected_to locations_url
    assert_equal "Renamed cupboard", location.reload.name
    assert location.hidden?
    assert_nil location.parent_id
  end

  #-----------------------------------------------------------------------------
  test "deleting occupied locations reports a useful failure while empty leaves remain deletable" do
    child = @user.locations.create!(name: "Drawer M", parent: @root)
    shop = @user.shops.create!(name: "Location deletion supplier")
    stock = @user.inventory_items.create!(name: "Retained fixture screws", shop: shop, location: child, qty_have: 3)

    # Neither a child location nor its inventory may disappear through an ancestor.
    [@root, child].each do |location|
      assert_no_difference(["Location.count", "InventoryItem.count"]) do
        delete location_url(location)
        assert_redirected_to location_url(location)
      end
      assert flash[:alert].present?, "Deletion restrictions should explain why the location was retained"
    end
    assert_equal child.id, stock.reload.location_id

    # The restriction does not prevent deleting a separate unused leaf.
    empty_leaf = @user.locations.create!(name: "Empty pouch", parent: child)
    assert_difference("Location.count", -1) do
      delete location_url(empty_leaf)
      assert_redirected_to locations_url
    end
    assert Location.exists?(child.id)
    assert InventoryItem.exists?(stock.id)
  end
end
