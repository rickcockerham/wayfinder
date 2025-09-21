# app/models/item.rb
class Item < ApplicationRecord
  belongs_to :category
  belongs_to :mood

  belongs_to :parent, class_name: "Item", optional: true
  has_many   :children, class_name: "Item", foreign_key: :parent_id, dependent: :nullify

  has_many :blocking_edges,      class_name: "ItemBlock", foreign_key: :blocked_id, dependent: :destroy
  has_many :blockers,            through: :blocking_edges, source: :blocker

  has_many :blocking_out_edges,  class_name: "ItemBlock", foreign_key: :blocker_id, dependent: :destroy
  has_many :blocks,              through: :blocking_out_edges, source: :blocked

  has_many :material_requirements, dependent: :destroy
  has_many :item_inventories, dependent: :destroy
  has_many :reserved_inventory_items, through: :item_inventories, source: :inventory_item

  validates :title, presence: true

  DEFAULT_ESTIMATE = 30.freeze

  def missing_materials_by(inventory_hash)
    material_requirements.filter_map do |mr|
      have = inventory_hash[mr.name.downcase]&.qty_have.to_f
      short = mr.qty_needed.to_f - have
      short > 0 ? { name: mr.name, short:, unit: mr.unit, shop: mr.shop&.name } : nil
    end
  end

  def ready_now?(inventory_hash:)
    blockers.none? && missing_materials_by(inventory_hash).empty? && !done?
  end

  IMPORTANCE = {
    weights:        { personal: 2.0, emotional: 3.0, family: 2.0 },
    horizon_days:   30,
    u_weight:       15.0,  # max pressure at deadline day
    overdue_cap:    30,
    overdue_per:    2.0,
    # Time penalty (NEW)
    time_per_hour:  0.5,   # points removed per hour
    time_cap_hours: 20,    # cap hours counted toward penalty
    # Optional quick-task bonus (leave 0.0 to disable)
    quick_minutes:  30,
    quick_bonus:    10.0
  }.freeze

  def importance_score(today: Date.current)
    w  = IMPORTANCE[:weights]
    h  = IMPORTANCE[:horizon_days].to_f
    uw = IMPORTANCE[:u_weight].to_f

    impact = w[:personal]*personal_impact.to_f +
             w[:emotional]*emotional_impact.to_f +
             w[:family]*family_impact.to_f

    upcoming = 0.0
    overdue  = 0.0
    if deadline.present?
      days = (deadline - today).to_i
      if days >= 0
        frac = [[days / h, 1.0].min, 0.0].max
        upcoming = uw * (1.0 - frac)
      else
        o = [[-days, IMPORTANCE[:overdue_cap]].min, 0].max
        overdue = o * IMPORTANCE[:overdue_per].to_f
      end
    end

    # NEW: time penalty
    hours = [time_estimate_minutes.to_i, 0].max / 60.0
    time_penalty = - [hours, IMPORTANCE[:time_cap_hours]].min * IMPORTANCE[:time_per_hour]

    quick = if time_estimate_minutes.to_i > 0 &&
               time_estimate_minutes.to_i <= IMPORTANCE[:quick_minutes]
              IMPORTANCE[:quick_bonus].to_f
            else
              0.0
            end

    (impact + upcoming + overdue + time_penalty + quick).round(3)
  end


  def self.importance_sql(today: Date.current)
    t  = table_name # "items"
    w  = IMPORTANCE[:weights]
    d  = "DATEDIFF(#{t}.deadline, '#{today}')"

    impacts =
      "#{w[:personal]}*COALESCE(#{t}.personal_impact,0) +" \
      " #{w[:emotional]}*COALESCE(#{t}.emotional_impact,0) +" \
      " #{w[:family]}*COALESCE(#{t}.family_impact,0)"

    h        = IMPORTANCE[:horizon_days]
    u_weight = IMPORTANCE[:u_weight]
    upcoming = "#{u_weight} * (1 - LEAST(GREATEST(#{d},0)/#{h}.0, 1))"

    cap   = IMPORTANCE[:overdue_cap]
    per_d = IMPORTANCE[:overdue_per]
    overdue = "CASE WHEN #{d} < 0 THEN LEAST(ABS(#{d}), #{cap}) * #{per_d} ELSE 0 END"

    time_h       = "COALESCE(#{t}.time_estimate_minutes,0)/60.0"
    time_penalty = "- LEAST(#{time_h}, #{IMPORTANCE[:time_cap_hours]}) * #{IMPORTANCE[:time_per_hour]}"

    qmin  = IMPORTANCE[:quick_minutes]
    qbon  = IMPORTANCE[:quick_bonus]
    quick = "CASE WHEN COALESCE(#{t}.time_estimate_minutes,0) > 0 AND " \
            "COALESCE(#{t}.time_estimate_minutes,0) <= #{qmin} THEN #{qbon} ELSE 0 END"

    "(#{impacts}) + (CASE WHEN #{t}.deadline IS NULL THEN 0 ELSE (#{upcoming}) + (#{overdue}) END) + (#{time_penalty}) + (#{quick})"
  end

  scope :order_by_importance, ->(today: Date.current) {
    t = table_name
    order(
      Arel.sql(
        "#{importance_sql(today: today)} DESC, " \
        "COALESCE(#{t}.deadline, '9999-12-31'), " \
        "#{t}.time_estimate_minutes ASC"
      )
    )
  }

  enum recurrence_kind: { no_recurrence: 0, fixed_schedule: 1, after_completion: 2 }
  enum recurrence_unit: { day: 0, week: 1, month: 2, year: 3 }

  # ...existing associations/validations...

  # Set initial deadline to start date if given and no deadline yet
  before_validation :apply_recurrence_start_to_deadline, on: :create

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

  def apply_recurrence_start_to_deadline
    return if deadline.present?
    self.deadline = recurrence_start_on if recurrence_start_on.present?
  end

  # === Recurrence calculators ===

  # For Type 1 (fixed_schedule): schedule strictly by the prior scheduled deadline
  def next_deadline_from_schedule
    base = (deadline || recurrence_start_on)
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
end
