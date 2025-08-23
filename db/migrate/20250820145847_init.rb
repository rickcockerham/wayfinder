class Init < ActiveRecord::Migration[7.1]
  def change
    # --- Lookup tables ---
    create_table :categories do |t|
      t.string :name, null: false
      t.index :name, unique: true
      t.timestamps
    end

    create_table :moods do |t|
      t.string :name, null: false
      t.index :name, unique: true
      t.timestamps
    end

    create_table :locations do |t|
      t.string :name, null: false
      t.index :name, unique: true
      t.timestamps
    end

    create_table :shops do |t|
      t.string :name, null: false
      t.index :name, unique: true
      t.timestamps
    end

    # --- Core items ---
    create_table :items do |t|
      t.string  :title, null: false
      t.text    :notes

      t.references :category, null: false, foreign_key: true
      t.references :mood,     null: false, foreign_key: true
      t.references :parent,   foreign_key: { to_table: :items, on_delete: :nullify }

      t.integer :personal_impact,  default: 0, null: false
      t.integer :emotional_impact, default: 0, null: false
      t.integer :family_impact,    default: 0, null: false

      t.integer :time_estimate_minutes, default: 0, null: false
      t.integer :cost_cents,            default: 0, null: false

      t.date    :deadline
      t.boolean :done, default: false, null: false

      t.timestamps
    end
    add_index :items, :deadline
    add_index :items, :done
    add_index :items, :time_estimate_minutes

    # --- Item dependency edges (blockers) ---
    create_table :item_blocks do |t|
      t.bigint :blocker_id, null: false
      t.bigint :blocked_id, null: false
    end
    add_index :item_blocks, [:blocker_id, :blocked_id], unique: true
    add_index :item_blocks, :blocked_id
    add_foreign_key :item_blocks, :items, column: :blocker_id, on_delete: :cascade
    add_foreign_key :item_blocks, :items, column: :blocked_id, on_delete: :cascade

    # --- Materials required per item (optional preferred shop) ---
    create_table :material_requirements do |t|
      t.references :item, null: false, foreign_key: { on_delete: :cascade }
      t.string  :name, null: false
      t.decimal :qty_needed, precision: 10, scale: 2, null: false, default: 1
      t.string  :unit, default: "", null: false
      t.references :shop, foreign_key: true # preferred vendor (optional)
      t.timestamps
    end
    add_index :material_requirements, [:item_id, :name], unique: true

    # --- Inventory on hand (by location) ---
    create_table :inventory_items do |t|
      t.string  :name, null: false
      t.decimal :qty_have, precision: 10, scale: 2, null: false, default: 0
      t.string  :unit, default: "", null: false
      t.references :location, foreign_key: true
      t.timestamps
    end
    # Allow the same item name in different locations; enforce uniqueness per location.
    add_index :inventory_items, [:name, :location_id], unique: true
  end
end
