class ImportanceSetting < ApplicationRecord
  DEFAULTS = {
    personal_weight: 2.0,
    emotional_weight: 3.0,
    family_weight: 2.0,
    horizon_days: 30,
    urgency_weight: 15.0,
    overdue_cap_days: 30,
    overdue_per_day: 2.0,
    time_penalty_per_level: 0.5,
    time_penalty_max_level: 7,
    quick_task_max_level: 0,
    quick_task_bonus: 10.0,
    planner_morning_start_minute: 300,
    planner_afternoon_start_minute: 720,
    planner_evening_start_minute: 1080,
    timezone: "Central Time (US & Canada)"
  }.freeze

  TIMEZONE_OPTIONS = ActiveSupport::TimeZone.all.map(&:name).freeze

  belongs_to :user

  validates :personal_weight, :emotional_weight, :family_weight, :urgency_weight,
            :overdue_per_day, :time_penalty_per_level,
            :quick_task_bonus, numericality: true
  validates :horizon_days, :overdue_cap_days, :time_penalty_max_level, :quick_task_max_level,
            :planner_morning_start_minute, :planner_afternoon_start_minute, :planner_evening_start_minute,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :time_penalty_max_level, :quick_task_max_level, inclusion: { in: 0..7 }
  validates :planner_morning_start_minute, :planner_afternoon_start_minute, :planner_evening_start_minute,
            numericality: { less_than: 1440 }
  validates :personal_weight, :emotional_weight, :family_weight, :urgency_weight,
            :overdue_per_day, :time_penalty_per_level,
            :quick_task_bonus, numericality: { greater_than_or_equal_to: 0 }
  validates :timezone, inclusion: { in: TIMEZONE_OPTIONS }
  validate :planner_times_in_order

  def self.default_attributes
    DEFAULTS.dup
  end

  def planner_slots
    [
      { key: "morning", label: "Morning", start_minute: planner_morning_start_minute, end_minute: planner_afternoon_start_minute },
      { key: "afternoon", label: "Afternoon", start_minute: planner_afternoon_start_minute, end_minute: planner_evening_start_minute },
      { key: "evening", label: "Evening", start_minute: planner_evening_start_minute, end_minute: nil }
    ].map do |slot|
      range_label =
        if slot[:end_minute]
          "#{minute_label(slot[:start_minute])} - #{minute_label(slot[:end_minute])}"
        else
          "#{minute_label(slot[:start_minute])} onward"
        end

      slot.merge(full_label: "#{slot[:label]} (#{range_label})")
    end
  end

  def day_part_for(time)
    local_time = time.in_time_zone(timezone)
    minutes = (local_time.hour * 60) + local_time.min

    return nil if minutes < planner_morning_start_minute
    return "morning" if minutes < planner_afternoon_start_minute
    return "afternoon" if minutes < planner_evening_start_minute

    "evening"
  end

  def current_local_date(now = Time.current)
    now.in_time_zone(timezone).to_date
  end

  def minute_label(total_minutes)
    hour = total_minutes / 60
    minute = total_minutes % 60
    Time.utc(2000, 1, 1, hour, minute).strftime("%-I:%M %p")
  end

  private

  def planner_times_in_order
    return if planner_morning_start_minute < planner_afternoon_start_minute &&
              planner_afternoon_start_minute < planner_evening_start_minute

    errors.add(:base, "Planner times must be in morning, afternoon, evening order.")
  end
end
