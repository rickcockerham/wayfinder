class AddUsersAndOwnership < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :access_key, null: false
      t.timestamps
    end

    add_index :users, :access_key, unique: true

    # Create default user for backfill using raw SQL
    access_key = SecureRandom.hex(16)
    execute <<-SQL
      INSERT INTO users (name, access_key, created_at, updated_at)
      VALUES ('Default', '#{access_key}', NOW(), NOW())
    SQL

    # Add user_id columns as nullable, backfill, then make NOT NULL
    tables = [:categories, :moods, :shops, :locations, :inventory_items, :items, :item_blocks, :material_requirements, :item_inventories, :schedule_entries]
    
    tables.each do |table|
      add_reference table, :user, foreign_key: true
      execute "UPDATE #{table} SET user_id = (SELECT id FROM users WHERE access_key = '#{access_key}') WHERE user_id IS NULL"
      change_column_null table, :user_id, false
    end
  end
end
