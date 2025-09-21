class Weeklything < ActiveRecord::Migration[7.1]
  def change
    create_table :schedule_entries do |t|
      t.date :on_date, null: false
      t.integer :day_part, null: false, default: 0   # enum: 0=morning,1=afternoon,2=evening
      t.references :category, null: false, foreign_key: true
      t.timestamps
    end

    add_index :schedule_entries, [:on_date, :day_part]
    add_index :schedule_entries, [:on_date, :day_part, :category_id], unique: true, name: "idx_schedule_entries_unique_slot"
  end
end
