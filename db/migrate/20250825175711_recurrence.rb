# db/migrate/20250825_add_recurrence_to_items.rb
class Recurrence < ActiveRecord::Migration[7.1]
  def change
    change_table :items, bulk: true do |t|
      t.integer :recurrence_kind, null: false, default: 0
      # 0: none, 1: fixed_schedule, 2: after_completion

      t.integer :recurrence_unit, null: false, default: 0
      # 0: day, 1: week, 2: month, 3: year

      t.integer :recurrence_interval, null: false, default: 1       # e.g. 10 days, 3 months, etc.
      t.integer :recurrence_day_of_month                            # e.g. 1 -> 1st of month
      t.integer :recurrence_month_of_year                           # e.g. 10 -> October (for Oct 17th)
      t.date    :recurrence_start_on                                # “start date” (first deadline)
      t.datetime :completed_at
    end

    add_index :items, :recurrence_kind
    add_index :items, [:recurrence_unit, :recurrence_interval]
    add_index :items, [:recurrence_day_of_month, :recurrence_month_of_year]
  end
end
