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

  def initialize(hours:, mood:, category: nil, quick: nil, user: Current.user)
    @hours, @mood, @category, @quick = hours, mood&.to_s&.downcase, category&.to_s&.downcase, quick
    @user = user
  end

  def call
    inv = InventoryItem.for_user(@user).includes(:location).index_by { |i| i.name.downcase }

    scope = Item.for_user(@user).includes(:category, :mood, :blockers, :material_requirements).where(done: false).visible_on_list
    scope = scope.joins(:category).where(categories: { name: @category }) if @category.present?
    scope = scope.where("time_scale <= ?", time_scale_for_hours(@hours)) if @hours
    scope = scope.where(@quick ? ["time_scale <= ?", 0] : ["time_scale >= ?", 0])

    weights = DEFAULT_WEIGHTS.dup
    if @mood && DEFAULT_WEIGHTS[:mood_bias][@mood.to_sym]
      mb = DEFAULT_WEIGHTS[:mood_bias][@mood.to_sym]
      weights[:personal] = mb[:personal]; weights[:emotional] = mb[:emotional]; weights[:family] = mb[:family]
    end

    candidates = scope.to_a
    candidates.select! { |it| it.ready_now?(inventory_hash: inv) }
    candidates.sort_by { |it| -it.importance_score }
  end

  private

  def time_scale_for_hours(hours)
    value = hours.to_f
    return 0 if value <= 0.5
    return 1 if value <= 1
    return 2 if value <= 8
    return 3 if value <= 24
    return 4 if value <= 24 * 7
    return 5 if value <= 24 * 30
    return 6 if value <= 24 * 365

    7
  end
end
