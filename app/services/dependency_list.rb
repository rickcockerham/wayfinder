# app/services/dependency_list.rb
class DependencyList
  def initialize(items)
    @items = items # Array<Item> with :blocks and :blockers preloaded
  end

  def call
    items    = @items.to_a
    ids      = items.map(&:id).compact
    idset    = ids.to_set
    imp_byId = items.to_h { |it| [it.id, importance(it)] }

    # Build adjacency (blocker -> blocked) and reverse (blocked -> blockers)
    edges = Hash.new { |h,k| h[k] = [] } # id => [Item children]
    rev   = Hash.new { |h,k| h[k] = [] } # id => [Item blockers]

    items.each do |it|
      Array(it.blocks).each do |child|
        next unless child&.id && idset.include?(child.id)
        edges[it.id] << child
        rev[child.id] << it
      end
    end

    # Primary blocker per child = highest-importance blocker present
    primary = {}
    rev.each do |child_id, blks|
      primary[child_id] = blks.max_by { |b| imp_byId[b.id] || 0 }&.id
    end

    # Roots have no primary blocker in this set; sort roots by importance
    roots = items.select { |it| primary[it.id].nil? }
    roots.sort_by! { |it| -(imp_byId[it.id] || 0) }

    visited = {}
    order   = []

    dfs = lambda do |node|
      nid = node.id
      return if visited[nid]
      visited[nid] = true
      order << node
      children = (edges[nid] || []).select { |c| primary[c.id] == nid }
      children.sort_by! { |c| -(imp_byId[c.id] || 0) }
      children.each { |c| dfs.call(c) }
    end

    roots.each { |r| dfs.call(r) }
    # any stragglers (cycles or blockers outside the set)
    items.each { |it| dfs.call(it) unless visited[it.id] }

    order
  end

  private

  def importance(item)
    item.respond_to?(:importance_score) ? item.importance_score : 0.0
  end
end
