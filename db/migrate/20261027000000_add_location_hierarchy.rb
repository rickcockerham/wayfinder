class AddLocationHierarchy < ActiveRecord::Migration[7.1]
  # -----------------------------------------------------------------------------
  def up
    add_column :inventory_items, :aliases, :text
    # A generated non-null key also enforces uniqueness for root siblings in MySQL.
    add_reference :locations, :parent, foreign_key: { to_table: :locations }
    add_column :locations, :parent_key, :virtual, type: :bigint,
      as: "COALESCE(parent_id, 0)", stored: true
    add_index :locations, [:user_id, :parent_key, :name], unique: true,
      name: "idx_locations_sibling_name"
    remove_index :locations, name: "idx_locations_user_name"
  end

  # -----------------------------------------------------------------------------
  def down
    # Never flatten a populated hierarchy or silently merge repeated branch names.
    if select_value("SELECT COUNT(*) FROM locations WHERE parent_id IS NOT NULL").to_i.positive?
      raise ActiveRecord::IrreversibleMigration, "Nested locations must be reviewed before rollback"
    end
    add_index :locations, [:user_id, :name], unique: true, name: "idx_locations_user_name"
    remove_index :locations, name: "idx_locations_sibling_name"
    remove_column :locations, :parent_key
    remove_reference :locations, :parent, foreign_key: { to_table: :locations }
    remove_column :inventory_items, :aliases
  end
end
