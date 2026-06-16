# app/models/item.rb
class Item < ApplicationRecord
  belongs_to :user
  belongs_to :category
  belongs_to :mood

  belongs_to :parent, class_name: "Item", optional: true
  has_many   :children, class_name: "Item", foreign_key: :parent_id, dependent: :nullify

  has_many :blocking_edges,      class_name: "ItemBlock", foreign_key: :blocked_id, dependent: :destroy
  has_many :blockers,            through: :blocking_edges, source: :blocker
  has_many :active_blocking_edges,
           -> {
             joins(:blocker).where(items: { done: false })
           },
           class_name: "ItemBlock",
           foreign_key: :blocked_id
  has_many :unresolved_blockers,
           through: :active_blocking_edges,
           source: :blocker

  has_many :blocking_out_edges,  class_name: "ItemBlock", foreign_key: :blocker_id, dependent: :destroy
  has_many :blocks,              through: :blocking_out_edges, source: :blocked

  has_many :material_requirements, dependent: :destroy
  has_many :item_inventories, dependent: :destroy
  has_many :reserved_inventory_items, through: :item_inventories, source: :inventory_item

  validates :title, presence: true
  validates :hide_days, numericality: { greater_than_or_equal_to: 0 }
  validates :time_scale, inclusion: { in: 0..7 }
  validate :category_belongs_to_user
  validate :mood_belongs_to_user
  validate :parent_belongs_to_user

  TIME_SCALE_LABELS = [
    "Quick",
    "Minutes",
    "Hours",
    "Days",
    "Weeks",
    "Months",
    "Years",
    "Forever"
  ].freeze

  def missing_materials_by(inventory_hash)
    material_requirements.filter_map do |mr|
      have = inventory_hash[mr.name.downcase]&.qty_have.to_f
      short = mr.qty_needed.to_f - have
      short > 0 ? { name: mr.name, short:, unit: mr.unit, shop: mr.shop&.name } : nil
    end
  end

  def ready_now?(inventory_hash:)
    unresolved_blockers.none? && missing_materials_by(inventory_hash).empty? && !done?
  end

  def reactivate_blockers!(visited_ids = [])
    return if visited_ids.include?(id)
    visited_ids << id

    blockers.where(done: true).to_a.each do |blocker|
      blocker.update_columns(done: false, completed_at: nil)
      blocker.reactivate_blockers!(visited_ids)
    end
  end

  def importance_score(today: Date.current)
    settings = importance_settings
    h  = settings.horizon_days.to_f
    uw = settings.urgency_weight.to_f

    impact = settings.personal_weight.to_f * personal_impact.to_f +
             settings.emotional_weight.to_f * emotional_impact.to_f +
             settings.family_weight.to_f * family_impact.to_f

    upcoming = 0.0
    overdue  = 0.0
    if deadline.present?
      days = (deadline - today).to_i
      if days >= 0
        frac = [[days / h, 1.0].min, 0.0].max
        upcoming = uw * (1.0 - frac)
      else
        o = [[-days, settings.overdue_cap_days].min, 0].max
        overdue = o * settings.overdue_per_day.to_f
      end
    end

    time_level = [time_scale.to_i, 0].max
    time_penalty = - [time_level, settings.time_penalty_max_level.to_i].min * settings.time_penalty_per_level.to_f

    quick = if time_level <= settings.quick_task_max_level.to_i
              ratio = (settings.quick_task_max_level.to_i - time_level + 1).to_f / (settings.quick_task_max_level.to_i + 1).to_f
              settings.quick_task_bonus.to_f * ratio
            else
              0.0
            end

    (impact + upcoming + overdue + time_penalty + quick).round(3)
  end

  def self.importance_sql(today: Date.current, settings: ImportanceSetting.new(ImportanceSetting.default_attributes))
    t  = table_name # "items"
    d  = "DATEDIFF(#{t}.deadline, '#{today}')"

    impacts =
      "#{settings.personal_weight}*COALESCE(#{t}.personal_impact,0) +" \
      " #{settings.emotional_weight}*COALESCE(#{t}.emotional_impact,0) +" \
      " #{settings.family_weight}*COALESCE(#{t}.family_impact,0)"

    h        = settings.horizon_days
    u_weight = settings.urgency_weight
    upcoming = "#{u_weight} * (1 - LEAST(GREATEST(#{d},0)/#{h}.0, 1))"

    cap   = settings.overdue_cap_days
    per_d = settings.overdue_per_day
    overdue = "CASE WHEN #{d} < 0 THEN LEAST(ABS(#{d}), #{cap}) * #{per_d} ELSE 0 END"

    time_level   = "COALESCE(#{t}.time_scale,0)"
    time_penalty = "- LEAST(#{time_level}, #{settings.time_penalty_max_level}) * #{settings.time_penalty_per_level}"

    qmax  = settings.quick_task_max_level
    qbon  = settings.quick_task_bonus
    quick = "CASE WHEN COALESCE(#{t}.time_scale,0) <= #{qmax} " \
            "THEN #{qbon} * ((#{qmax} - COALESCE(#{t}.time_scale,0) + 1.0) / (#{qmax} + 1.0)) ELSE 0 END"

    "(#{impacts}) + (CASE WHEN #{t}.deadline IS NULL THEN 0 ELSE (#{upcoming}) + (#{overdue}) END) + (#{time_penalty}) + (#{quick})"
  end

  scope :order_by_importance, ->(today: Date.current) {
    t = table_name
    settings = ImportanceSetting.new(ImportanceSetting.default_attributes)
    order(
      Arel.sql(
        "#{importance_sql(today: today, settings: settings)} DESC, " \
        "COALESCE(#{t}.deadline, '9999-12-31'), " \
        "#{t}.time_scale ASC"
      )
    )
  }

  scope :without_active_blockers, -> {
    false_value = connection.quote(false)

    where(<<~SQL.squish)
      NOT EXISTS (
        SELECT 1
        FROM #{ItemBlock.quoted_table_name}
        INNER JOIN #{quoted_table_name} active_blockers
          ON active_blockers.id = #{ItemBlock.quoted_table_name}.blocker_id
        WHERE #{ItemBlock.quoted_table_name}.blocked_id = #{quoted_table_name}.id
          AND #{ItemBlock.quoted_table_name}.user_id = #{quoted_table_name}.user_id
          AND active_blockers.user_id = #{quoted_table_name}.user_id
          AND active_blockers.done = #{false_value}
      )
    SQL
  }

  #-----------------------------------------
  scope :visible_on_list, ->(today: Date.current) {
    t = table_name
    hide_days_sql = "COALESCE(#{t}.hide_days, 0)"
    where(
      "#{t}.deadline IS NULL OR #{hide_days_sql} <= 0 OR DATEDIFF(#{t}.deadline, ?) < #{hide_days_sql}",
      today
    )
  }

  enum recurrence_kind: { no_recurrence: 0, fixed_schedule: 1, after_completion: 2 }
  enum recurrence_unit: { day: 0, week: 1, month: 2, year: 3 }

  before_validation :inherit_user_from_associations
  before_validation :normalize_time_scale

  validates :recurrence_interval, numericality: { greater_than_or_equal_to: 1 }
  validates :recurrence_day_of_month, inclusion: { in: 1..31 }, allow_nil: true
  validates :recurrence_month_of_year, inclusion: { in: 1..12 }, allow_nil: true
  validate  :validate_rule_combination

  def validate_rule_combination
    # If a yearly specific date is desired, both month & day should be present
    if recurrence_unit == "year" && recurrence_month_of_year.present? ^ recurrence_day_of_month.present?
      errors.add(:base, "Both month_of_year and day_of_month must be set for a specific yearly date")
    end
  end

  def inherit_user_from_associations
    self.user ||= category&.user || mood&.user || parent&.user
  end

  def category_belongs_to_user
    validate_associated_user(:category)
  end

  def mood_belongs_to_user
    validate_associated_user(:mood)
  end

  def parent_belongs_to_user
    validate_associated_user(:parent)
  end

  def recurrence_schedule_description
    return nil if no_recurrence?

    interval = recurrence_interval.to_i
    unit = interval == 1 ? recurrence_unit : recurrence_unit.pluralize
    description = "Every #{interval} #{unit}"

    if recurrence_unit == "month" && recurrence_day_of_month.present?
      description += " on day #{recurrence_day_of_month}"
    elsif recurrence_unit == "year" && recurrence_month_of_year.present? && recurrence_day_of_month.present?
      description += " on #{Date::MONTHNAMES[recurrence_month_of_year]} #{recurrence_day_of_month}"
    end

    "#{description}."
  end

  #-----------------------------------------
  def visible_on_list?(today: Date.current)
    return true if deadline.blank?
    return true if hide_days.to_i <= 0

    (deadline - today).to_i < hide_days.to_i
  end

  def importance_settings
    user&.importance_setting || ImportanceSetting.new(ImportanceSetting.default_attributes)
  end

  def time_scale_label
    TIME_SCALE_LABELS[time_scale.to_i] || "Unknown"
  end

  def self.normalize_time_scale_value(value)
    level = value.to_i
    return level if (0..7).cover?(level)
    return 0 if level <= 30
    return 1 if level <= 60
    return 2 if level <= 8 * 60
    return 3 if level <= 24 * 60
    return 4 if level <= 7 * 24 * 60
    return 5 if level <= 30 * 24 * 60
    return 6 if level <= 365 * 24 * 60

    7
  end

  # === Recurrence calculators ===

  # For Type 1 (fixed_schedule): schedule strictly by the prior scheduled deadline
  def next_deadline_from_schedule
    base = deadline
    return nil if base.nil? || no_recurrence?
    RecurrenceRules.next_occurrence(
      unit: recurrence_unit.to_sym,
      interval: recurrence_interval,
      base_date: base,
      day_of_month: recurrence_day_of_month,
      month_of_year: recurrence_month_of_year
    )
  end

  # For Type 2 (after_completion): schedule from when you actually finished
  def next_deadline_from_completion(completed_on: (completed_at&.to_date || Date.current))
    return nil if no_recurrence?
    RecurrenceRules.next_occurrence(
      unit: recurrence_unit.to_sym,
      interval: recurrence_interval,
      base_date: completed_on,
      day_of_month: recurrence_day_of_month,
      month_of_year: recurrence_month_of_year
    )
  end

  private

  def normalize_time_scale
    self.time_scale = self.class.normalize_time_scale_value(time_scale)
  end
end
