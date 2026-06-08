require "test_helper"

class ItemTest < ActiveSupport::TestCase
  fixtures []

  test "an item with only done blockers is treated as unblocked" do
    category = Category.create!(name: "Test")
    mood = Mood.create!(name: "Test")

    blocker = Item.create!(title: "Blocker", category: category, mood: mood, done: true)
    blocked = Item.create!(title: "Blocked", category: category, mood: mood, done: false)
    blocked.blockers << blocker

    assert_equal 1, blocked.blockers.count
    assert_empty blocked.unresolved_blockers
    assert blocked.ready_now?(inventory_hash: {})
  end

  test "reactivating an item also reactivates done blockers" do
    category = Category.create!(name: "Test parent")
    mood = Mood.create!(name: "Test mood")

    blocker = Item.create!(title: "Blocker", category: category, mood: mood, done: true, completed_at: Time.current)
    blocked = Item.create!(title: "Blocked", category: category, mood: mood, done: true, completed_at: Time.current)
    blocked.blockers << blocker

    blocked.update!(done: false, completed_at: nil)
    blocked.reactivate_blockers!

    assert_not blocker.reload.done?
    assert_nil blocker.reload.completed_at
  end
end
