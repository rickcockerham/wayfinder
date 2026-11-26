require "test_helper"

class ItemBlockTest < ActiveSupport::TestCase
  #-----------------------------------------------------------------------------
  test "native validation rejects self links cycles duplicate and foreign owners but permits safe edits" do
    user = users(:default_user)
    a,b,c,d = %w[A B C D].map { |name| user.items.create!(title: "Graph model #{name}", category: categories(:default_category), mood: moods(:default_mood)) }
    first = user.item_blocks.create!(blocker: a, blocked: b)
    user.item_blocks.create!(blocker: b, blocked: c)
    last = user.item_blocks.create!(blocker: c, blocked: d)
    assert_not user.item_blocks.new(blocker: a, blocked: a).valid?
    assert_not user.item_blocks.new(blocker: a, blocked: b).valid?
    assert_not user.item_blocks.new(blocker: c, blocked: a).valid?
    assert_not last.update(blocked: a)
    assert_equal d.id, last.reload.blocked_id
    assert first.update(blocked: d)
    other = User.create!(name: "Graph private owner", access_key: "graph-private-test-only")
    assert_not other.item_blocks.new(blocker: a, blocked: b).valid?
  end

  #-----------------------------------------------------------------------------
  test "legacy cycles do not hang validation and foreign key cascades clean both endpoints" do
    user = users(:default_user)
    a,b,c,d = %w[A B C D].map { |name| user.items.create!(title: "Legacy graph #{name}", category: categories(:default_category), mood: moods(:default_mood)) }
    one = user.item_blocks.create!(blocker: a, blocked: b)
    two = user.item_blocks.create!(blocker: b, blocked: c)
    legacy = user.item_blocks.new(blocker: c, blocked: a)
    legacy.save!(validate: false)
    assert user.item_blocks.new(blocker: d, blocked: b).valid?
    # Existing schema must also avoid dangling edges if a record is deleted below callbacks.
    Item.where(id: b.id).delete_all
    assert_not ItemBlock.exists?(one.id)
    assert_not ItemBlock.exists?(two.id)
    assert ItemBlock.exists?(legacy.id)
    [a,c,d].each { |item| assert Item.exists?(item.id) }
  end
end
