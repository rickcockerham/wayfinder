require "test_helper"

class HomeItemSelectionTest < ActiveSupport::TestCase
  # --------------------------------------------------------------------------
  test "empty search excludes completed records and search retains existing bypass" do
    user = users(:default_user)
    item = items(:one)
    item.update!(done: true, title: "Search fixture", deadline: Date.current + 10, hide_days: 1)
    filters = { q: "", mood_ids: [], category_id: nil, time_i: 7, sort: "importance" }
    assert_empty HomeItemSelection.new(user, filters).call
    assert_equal [item], HomeItemSelection.new(user, filters.merge(q: "search")).call
    assert_empty HomeItemSelection.new(user, filters.merge(q: "no match")).call
  end
end
