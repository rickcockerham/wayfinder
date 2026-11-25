class AllowUnknownInventoryQuantity < ActiveRecord::Migration[7.1]
  # -----------------------------------------------------------------------------
  def up
    # Preserve every existing value and the legacy web/model default of zero.
    change_column_null :inventory_items, :qty_have, true
  end

  # -----------------------------------------------------------------------------
  def down
    # A rollback must never turn an unknown count into a fabricated zero.
    if select_value("SELECT COUNT(*) FROM inventory_items WHERE qty_have IS NULL").to_i.positive?
      raise ActiveRecord::IrreversibleMigration, "Unknown inventory counts must be reviewed before rollback"
    end
    change_column_null :inventory_items, :qty_have, false
  end
end
