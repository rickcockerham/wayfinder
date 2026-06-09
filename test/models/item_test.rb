require "test_helper"

class ItemTest < ActiveSupport::TestCase
  fixtures []

  test "an item with only done blockers is treated as unblocked" do
    user = User.create!(name: "Test", access_key: "item-test-1")
    category = user.categories.create!(name: "Test")
    mood = user.moods.create!(name: "Test")

    blocker = user.items.create!(title: "Blocker", category: category, mood: mood, done: true)
    blocked = user.items.create!(title: "Blocked", category: category, mood: mood, done: false)
    blocked.blockers << blocker

    assert_equal 1, blocked.blockers.count
    assert_empty blocked.unresolved_blockers
    assert blocked.ready_now?(inventory_hash: {})
  end

  test "without_active_blockers keeps only items without unfinished blockers" do
    user = User.create!(name: "Test", access_key: "item-test-ready-scope")
    category = user.categories.create!(name: "Test")
    mood = user.moods.create!(name: "Test")

    ready = user.items.create!(title: "Ready", category: category, mood: mood, done: false)
    completed_blocker = user.items.create!(title: "Completed blocker", category: category, mood: mood, done: true)
    blocked_by_completed = user.items.create!(title: "Blocked by completed", category: category, mood: mood, done: false)
    blocked_by_completed.blockers << completed_blocker

    active_blocker = user.items.create!(title: "Active blocker", category: category, mood: mood, done: false)
    blocked_by_active = user.items.create!(title: "Blocked by active", category: category, mood: mood, done: false)
    blocked_by_active.blockers << active_blocker

    items = Item.for_user(user).where(done: false).without_active_blockers.to_a

    assert_includes items, ready
    assert_includes items, blocked_by_completed
    assert_includes items, active_blocker
    assert_not_includes items, blocked_by_active
  end

  test "reactivating an item also reactivates done blockers" do
    user = User.create!(name: "Test", access_key: "item-test-2")
    category = user.categories.create!(name: "Test parent")
    mood = user.moods.create!(name: "Test mood")

    blocker = user.items.create!(title: "Blocker", category: category, mood: mood, done: true, completed_at: Time.current)
    blocked = user.items.create!(title: "Blocked", category: category, mood: mood, done: true, completed_at: Time.current)
    blocked.blockers << blocker

    blocked.update!(done: false, completed_at: nil)
    blocked.reactivate_blockers!

    assert_not blocker.reload.done?
    assert_nil blocker.reload.completed_at
  end
end
