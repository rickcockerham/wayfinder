class AddPlannerTimesAndTimezoneToImportanceSettings < ActiveRecord::Migration[7.1]
  def change
    change_table :importance_settings, bulk: true do |t|
      t.integer :planner_morning_start_minute, null: false, default: 300
      t.integer :planner_afternoon_start_minute, null: false, default: 720
      t.integer :planner_evening_start_minute, null: false, default: 1080
      t.string :timezone, null: false, default: "Central Time (US & Canada)"
    end
  end
end
