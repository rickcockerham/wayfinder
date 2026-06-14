class CreateImportanceSettings < ActiveRecord::Migration[7.1]
  DEFAULTS = {
    personal_weight: 2.0,
    emotional_weight: 3.0,
    family_weight: 2.0,
    horizon_days: 30,
    urgency_weight: 15.0,
    overdue_cap_days: 30,
    overdue_per_day: 2.0,
    time_penalty_per_hour: 0.5,
    time_penalty_cap_hours: 20.0,
    quick_task_minutes: 30,
    quick_task_bonus: 10.0
  }.freeze

  def up
    create_table :importance_settings do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.float :personal_weight, null: false, default: DEFAULTS[:personal_weight]
      t.float :emotional_weight, null: false, default: DEFAULTS[:emotional_weight]
      t.float :family_weight, null: false, default: DEFAULTS[:family_weight]
      t.integer :horizon_days, null: false, default: DEFAULTS[:horizon_days]
      t.float :urgency_weight, null: false, default: DEFAULTS[:urgency_weight]
      t.integer :overdue_cap_days, null: false, default: DEFAULTS[:overdue_cap_days]
      t.float :overdue_per_day, null: false, default: DEFAULTS[:overdue_per_day]
      t.float :time_penalty_per_hour, null: false, default: DEFAULTS[:time_penalty_per_hour]
      t.float :time_penalty_cap_hours, null: false, default: DEFAULTS[:time_penalty_cap_hours]
      t.integer :quick_task_minutes, null: false, default: DEFAULTS[:quick_task_minutes]
      t.float :quick_task_bonus, null: false, default: DEFAULTS[:quick_task_bonus]
      t.timestamps
    end

    User.find_each do |user|
      user.create_importance_setting!(DEFAULTS)
    end
  end

  def down
    drop_table :importance_settings
  end
end
