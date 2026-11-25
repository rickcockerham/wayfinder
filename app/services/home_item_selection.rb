# Share the home page's filtering and ordering with read-only API callers.
class HomeItemSelection
  # --------------------------------------------------------------------------
  def initialize(user, filters)
    @user = user
    @filters = filters
  end

  # --------------------------------------------------------------------------
  def call
    scope = Item.for_user(@user).includes(:category, :mood, :material_requirements)
    unless @filters[:q].present?
      scope = scope.where(done: false).visible_on_list.without_active_blockers
    end
    scope = scope.where(mood_id: @filters[:mood_ids]) if @filters[:mood_ids].any?
    scope = scope.where(category_id: @filters[:category_id]) if @filters[:category_id].present?
    if @filters[:q].present?
      query = "%#{@filters[:q].downcase}%"
      scope = scope.where("LOWER(title) LIKE ? OR LOWER(notes) LIKE ?", query, query)
    end
    scope = scope.where("time_scale <= ?", @filters[:time_i]) if @filters[:time_i] < 7

    # Keep the original home sort, including its existing tie behavior.
    if @filters[:sort] == "time"
      scope.order(:time_scale, deadline: :asc).to_a
    else
      scope.to_a.sort_by { |item| -item.importance_score }
    end
  end
end
