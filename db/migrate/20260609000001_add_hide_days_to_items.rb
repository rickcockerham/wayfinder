class AddHideDaysToItems < ActiveRecord::Migration[7.1]
  def change
    add_column :items, :hide_days, :integer, null: false, default: 0
  end
end
