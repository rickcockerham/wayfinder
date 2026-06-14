class ScopeUniqueIndexesToUsers < ActiveRecord::Migration[7.1]
  def change
    remove_index :categories, name: "index_categories_on_name", if_exists: true
    add_index :categories, [:user_id, :name], unique: true, name: "idx_categories_user_name"

    remove_index :moods, name: "index_moods_on_name", if_exists: true
    add_index :moods, [:user_id, :name], unique: true, name: "idx_moods_user_name"

    remove_index :locations, name: "index_locations_on_name", if_exists: true
    add_index :locations, [:user_id, :name], unique: true, name: "idx_locations_user_name"

    remove_index :shops, name: "index_shops_on_name", if_exists: true
    add_index :shops, [:user_id, :name], unique: true, name: "idx_shops_user_name"

    remove_index :inventory_items, name: "index_inventory_items_on_name_and_location_id", if_exists: true
    add_index :inventory_items, [:user_id, :name, :location_id], unique: true, name: "idx_inventory_items_user_name_location"
  end
end
