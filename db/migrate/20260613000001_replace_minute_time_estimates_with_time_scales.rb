class ReplaceMinuteTimeEstimatesWithTimeScales < ActiveRecord::Migration[7.1]
  def up
    rename_column :items, :time_estimate_minutes, :time_scale if column_exists?(:items, :time_estimate_minutes)

    rename_column :importance_settings, :time_penalty_per_hour, :time_penalty_per_level if column_exists?(:importance_settings, :time_penalty_per_hour)
    rename_column :importance_settings, :time_penalty_cap_hours, :time_penalty_max_level if column_exists?(:importance_settings, :time_penalty_cap_hours)
    rename_column :importance_settings, :quick_task_minutes, :quick_task_max_level if column_exists?(:importance_settings, :quick_task_minutes)

    change_column_default :importance_settings, :time_penalty_max_level, from: 20.0, to: 7
    change_column_default :importance_settings, :quick_task_max_level, from: 30, to: 0
    change_column :importance_settings, :time_penalty_max_level, :integer
  end

  def down
    change_column :importance_settings, :time_penalty_max_level, :float
    change_column_default :importance_settings, :time_penalty_max_level, from: 7, to: 20.0
    change_column_default :importance_settings, :quick_task_max_level, from: 0, to: 30

    rename_column :importance_settings, :quick_task_max_level, :quick_task_minutes if column_exists?(:importance_settings, :quick_task_max_level)
    rename_column :importance_settings, :time_penalty_max_level, :time_penalty_cap_hours if column_exists?(:importance_settings, :time_penalty_max_level)
    rename_column :importance_settings, :time_penalty_per_level, :time_penalty_per_hour if column_exists?(:importance_settings, :time_penalty_per_level)

    rename_column :items, :time_scale, :time_estimate_minutes if column_exists?(:items, :time_scale)
  end
end
