class AddHiddenToReferenceLists < ActiveRecord::Migration[7.1]
  def change
    add_column :categories, :hidden, :boolean, null: false, default: false
    add_column :moods, :hidden, :boolean, null: false, default: false
    add_column :locations, :hidden, :boolean, null: false, default: false
    add_column :shops, :hidden, :boolean, null: false, default: false
  end
end
