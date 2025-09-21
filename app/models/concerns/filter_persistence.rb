# app/controllers/concerns/filter_persistence.rb
module FilterPersistence
  extend ActiveSupport::Concern

  FILTER_KEY = :filters_v2   # session key
  TTL        = 1.hour
  MAX_MINUTES = 6
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
      params.key?(:time_i) || params.key?(:quick) ||   # quick maps to 0
      params.key?(:sort)   || params.key?(:per)
  end

  # Merge incoming params
  def apply_params(base)
    out = base.dup
    out[:mood_ids] = Array(params[:mood_ids]).reject(&:blank?).map(&:to_i) if params.key?(:mood_ids)
    out[:category_id] = params[:category_id].presence&.to_i if params.key?(:category_id)
    if params.key?(:time_i)
      out[:time_i] = params[:time_i].to_i
    elsif params[:quick].present?
      out[:time_i] = 0
    end
    #out[:minutes] = params[:minutes].presence&.to_i if params.key?(:minutes)
    out[:sort] = params[:sort] if params.key?(:sort)
    out[:per]  = params[:per].presence&.to_i if params.key?(:per)
    out
  end

  def persist_filters!(hash)
    session[FILTER_KEY] = { "saved_at" => Time.current.to_i, "value" => hash }
    hash
  end

  def sanity(f)
    f[:mood_ids] ||= Mood.pluck(:id)
    f[:category_id] ||= nil
    #f[:minutes] = f[:minutes].to_i
    #f[:minutes] = MAX_MINUTES if f[:minutes] <= 0 || f[:minutes] > MAX_MINUTES
    # time_i: clamp to 0..7, default 7 (Forever)
    ti = f[:time_i].to_i
    f[:time_i] = (0..7).cover?(ti) ? ti : 7
    f[:sort] = %w[time importance].include?(f[:sort]) ? f[:sort] : "importance"
    f[:per]  = PER_OPTIONS.include?(f[:per].to_i) ? f[:per].to_i : 5
    f
  end

  def default_filters
    {
      mood_ids: Mood.pluck(:id),                 # all moods
      category_id: active_category_for_now&.id,  # ← planner drives default
      time_i: 7,
      #minutes: MAX_MINUTES,
      sort: "importance",
      per: 5
    }
  end

  # ===== Weekly Planner hookup =====

  # morning 05–11, afternoon 12–17, evening 18–22 (adjust if you like)
  def current_day_part(now = Time.zone ? Time.zone.now : Time.now)
    h = now.hour
    return "morning"   if (5..11).cover?(h)
    return "afternoon" if (12..17).cover?(h)
    return "evening"   if (18..22).cover?(h)
    nil
  end

  def active_category_for_now
    part = current_day_part
    return nil unless part
    today = (Time.zone || Time).now.to_date

    ScheduleEntry.where(on_date: today, day_part: part)
      .includes(:category)
      .order(updated_at: :desc)   # if multiple, the last one you touched “wins”
      .limit(1)
      .pick(:category_id)
      &.then { |id| Category.find_by(id: id) }
  end
end
