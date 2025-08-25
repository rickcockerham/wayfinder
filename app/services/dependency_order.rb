# app/services/dependency_order.rb
class DependencyOrder
  def initialize(items, importance_map:)
    @items = items.to_a
    @imp   = importance_map # { id => score } from MaxCascadeImportance
  end

  def call
    return @items if @items.empty?

    by_id  = @items.index_by(&:id)
    ids    = by_id.keys
    idset  = ids.to_set
    score  = ->(it) { @imp[it.id] || 0.0 }

    # Choose a SINGLE "primary blocker" for each item: the in-set blocker with highest score
    primary_for = {} # child_id => blocker_id (or nil)
    children_of = Hash.new { |h,k| h[k] = [] } # blocker_id => [child Items]

    @items.each do |it|
      in_set_blockers = Array(it.blockers).select { |b| b&.id && idset.include?(b.id) }
      pb = in_set_blockers.max_by { |b| score.call(b) }
      primary_for[it.id] = pb&.id
    end

    # Build children lists under that primary blocker
    @items.each do |it|
      pb = primary_for[it.id]
      children_of[pb] << it  # pb=nil means root bucket
    end

    # Sort roots by score (desc), then DFS placing each node followed by its children (also by score)
    roots = (children_of[nil] || []).sort_by { |it| -score.call(it) }

    visited = {}
    out = []

    visit = lambda do |node|
      return if visited[node.id]
      visited[node.id] = true
      out << node
      kids = (children_of[node.id] || []).sort_by { |c| -score.call(c) }
      kids.each { |c| visit.call(c) }
    end

    roots.each { |r| visit.call(r) }
    # safety: if any stragglers (cycles, etc.), append them in score order
    (@items - out).sort_by { |it| -score.call(it) }.each { |it| visit.call(it) }

    out
  end
end
