# app/controllers/concerns/filter_persistence.rb
module FilterPersistence
  extend ActiveSupport::Concern

  FILTER_KEY = :filters_v2   # session key
  TTL        = 1.hour
  PER_OPTIONS = [5, 20, 100].freeze
  TIME_INDEX_LABELS = [
    "Quick",  # 0
    "Minutes",       # 1
    "Hours",         # 2
    "Days",          # 3
    "Weeks",         # 4
    "Months",        # 5
    "Years",         # 6
    "Forever"        # 7
  ].freeze
  TIME_INDEX_LIMITS = [
    30,
    60,
    8 * 60,
    24 * 60,
    7 * 24 * 60,
    30 * 24 * 60,
    365 * 24 * 60,
    nil
  ].freeze

  included do
    helper_method :current_filters
  end

  def current_filters
    @filters ||= begin
      return persist_filters!(default_filters) if params[:reset_filters].present?

      # fresh session?
      if session[FILTER_KEY].is_a?(Hash) && session[FILTER_KEY]["saved_at"]
        if Time.at(session[FILTER_KEY]["saved_at"].to_i) > TTL.ago
          base = session[FILTER_KEY]["value"] || {}
          # if request carries any filter params, merge them into the saved one
          merged = apply_params(base.deep_symbolize_keys)
          return persist_filters!(sanity(merged))
        end
      end

      # no fresh saved filters — start from defaults and merge params (if any)
      persist_filters!(sanity(apply_params(default_filters)))
    end
  end

  private


  def any_filter_param?
    params.key?(:mood_ids) || params.key?(:category_id) ||
      params.key?(:time_i) || params.key?(:q) ||
      params.key?(:sort)   || params.key?(:per)
  end

  # Merge incoming params
  def apply_params(base)
    out = base.dup
    out[:mood_ids] = Array(params[:mood_ids]).reject(&:blank?).map(&:to_i) if params.key?(:mood_ids)
    out[:category_id] = params[:category_id].presence&.to_i if params.key?(:category_id)
    out[:time_i] = params[:time_i].to_i if params.key?(:time_i)
    out[:q] = params[:q].to_s.strip if params.key?(:q)
    out[:sort] = params[:sort] if params.key?(:sort)
    out[:per]  = params[:per].presence&.to_i if params.key?(:per)
    out
  end

  def persist_filters!(hash)
    session[FILTER_KEY] = { "saved_at" => Time.current.to_i, "value" => hash }
    hash
  end

  def sanity(f)
    allowed_mood_ids = Mood.for_user(current_user).visible.pluck(:id)
    f[:mood_ids] = if f[:mood_ids].present?
      Array(f[:mood_ids]).map(&:to_i) & allowed_mood_ids
    else
      allowed_mood_ids
    end

    category_id = f[:category_id].presence&.to_i
    f[:category_id] = Category.for_user(current_user).visible.exists?(id: category_id) ? category_id : nil
    ti = f[:time_i].to_i
    f[:time_i] = (0..7).cover?(ti) ? ti : 7
    f[:q] = f[:q].to_s.strip
    f[:sort] = %w[time importance].include?(f[:sort]) ? f[:sort] : "importance"
    f[:per]  = PER_OPTIONS.include?(f[:per].to_i) ? f[:per].to_i : 5
    f
  end

  def default_filters
    {
      mood_ids: Mood.for_user(current_user).visible.pluck(:id),                 # all moods
      category_id: active_category_for_now&.id,  # ← planner drives default
      time_i: 7,
      q: "",
      sort: "importance",
      per: 5
    }
  end

  # ===== Weekly Planner hookup =====
  def current_day_part(now = Time.zone ? Time.zone.now : Time.now)
    importance_setting.day_part_for(now)
  end

  def active_category_for_now
    part = current_day_part
    return nil unless part
    today = importance_setting.current_local_date

    ScheduleEntry.for_user(current_user).where(on_date: today, day_part: part)
      .includes(:category)
      .order(updated_at: :desc)   # if multiple, the last one you touched “wins”
      .limit(1)
      .pick(:category_id)
      &.then { |id| Category.for_user(current_user).find_by(id: id) }
  end

  def importance_setting
    @importance_setting ||= current_user.importance_setting || current_user.create_importance_setting!(ImportanceSetting.default_attributes)
  end
end
