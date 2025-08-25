# app/services/max_cascade_importance.rb
class MaxCascadeImportance
  def initialize(items, today: Date.current)
    @items = items.to_a
    @today = today
  end

  # => { item_id => cascaded_score }
  def call
    by_id   = @items.index_by(&:id)
    idset   = by_id.keys.to_set

    # Graph: blocker -> blocked (children within current set)
    children = Hash.new { |h,k| h[k] = [] }
    @items.each do |it|
      Array(it.blocks).each do |ch|
        next unless ch&.id && idset.include?(ch.id)
        children[it.id] << ch.id
      end
    end

    base  = @items.to_h { |it| [it.id, it.importance_score(today: @today)] }
    memo  = {}
    stack = {}

    dfs = lambda do |id|
      return memo[id] if memo.key?(id)
      return base[id] if stack[id] # cycle guard -> fall back to base
      stack[id] = true

      kid_ids = children[id]
      if kid_ids.any?
        child_max = kid_ids.map { |kid| dfs.call(kid) }.max
        memo[id]  = [base[id], child_max].max
      else
        memo[id] = base[id]
      end

      stack.delete(id)
      memo[id]
    end

    by_id.keys.each { |id| dfs.call(id) }
    memo
  end
end
