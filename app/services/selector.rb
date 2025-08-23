# app/services/selector.rb
class Selector
  DEFAULT_WEIGHTS = {
    personal: 3, emotional: 2, family: 2,
    urgency: 2,
    mood_bias: {
      work:     { personal:3, emotional:1, family:2 },
      play:     { personal:1, emotional:3, family:1 },
      building: { personal:2, emotional:2, family:2 }
    }
  }

  def initialize(hours:, mood:, category: nil, quick: nil)
    @hours, @mood, @category, @quick = hours, mood&.to_s&.downcase, category&.to_s&.downcase, quick
  end

  def call
    inv = InventoryItem.includes(:location).all.index_by { |i| i.name.downcase }

    scope = Item.includes(:category, :mood, :blockers, :material_requirements).where(done: false)
    scope = scope.joins(:category).where(categories: { name: @category }) if @category.present?
    scope = scope.where("time_estimate_minutes <= ?", (@hours * 60)) if @hours
    scope = scope.where(@quick ? ["time_estimate_minutes <= ?", 90] : ["time_estimate_minutes > 0"])

    weights = DEFAULT_WEIGHTS.dup
    if @mood && DEFAULT_WEIGHTS[:mood_bias][@mood.to_sym]
      mb = DEFAULT_WEIGHTS[:mood_bias][@mood.to_sym]
      weights[:personal] = mb[:personal]; weights[:emotional] = mb[:emotional]; weights[:family] = mb[:family]
    end

    candidates = scope.to_a
    candidates.select! { |it| it.ready_now?(inventory_hash: inv) }
    candidates.sort_by { |it| -it.score(hours: @hours, mood_weights: weights) }
  end
end
