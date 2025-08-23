class Iteminv < ActiveRecord::Migration[7.1]
  def change
    create_table :item_inventories do |t|
      t.references :item,            null: false, foreign_key: true
      t.references :inventory_item,  null: false, foreign_key: true
      t.decimal :qty_reserved, precision: 10, scale: 2, null: false, default: 0
      t.string  :unit, null: false, default: ""
      t.timestamps
    end
    add_index :item_inventories, [:item_id, :inventory_item_id], unique: true

  end
end
