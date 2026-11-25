# Verify only the disposable database, never the configured live application DB.
connection = ActiveRecord::Base.connection
raise "Wrong database" unless connection.current_database == "wayfinder_api_test_nested_20261027"
require Rails.root.join("db/migrate/20261027000000_add_location_hierarchy")
require Rails.root.join("db/migrate/20261027010000_allow_unknown_inventory_quantity")
raise "Unexpected hierarchy" unless connection.select_value("SELECT COUNT(*) FROM locations WHERE parent_id IS NOT NULL").to_i.zero?
raise "Unexpected unknown stock" unless connection.select_value("SELECT COUNT(*) FROM inventory_items WHERE qty_have IS NULL").to_i.zero?
migration = AddLocationHierarchy.new
quantity_migration = AllowUnknownInventoryQuantity.new
quantity_migration.migrate(:down)
migration.migrate(:down)
user_id = connection.select_value("SELECT id FROM users LIMIT 1").to_i
raise "Missing fixture owner" unless user_id.positive?
root_id = connection.insert("INSERT INTO locations (name,user_id,hidden,created_at,updated_at) VALUES ('migration preserved root',#{user_id},0,NOW(),NOW())")
shop_id = connection.insert("INSERT INTO shops (name,user_id,hidden,created_at,updated_at) VALUES ('migration test supplier',#{user_id},0,NOW(),NOW())")
stock_id = connection.insert("INSERT INTO inventory_items (name,user_id,location_id,shop_id,qty_have,unit,created_at,updated_at) VALUES ('migration preserved stock',#{user_id},#{root_id},#{shop_id},7.25,'each',NOW(),NOW())")
zero_id = connection.insert("INSERT INTO inventory_items (name,user_id,location_id,shop_id,unit,created_at,updated_at) VALUES ('migration preserved zero',#{user_id},#{root_id},#{shop_id},'each',NOW(),NOW())")
migration.migrate(:up)
quantity_migration.migrate(:up)
row = connection.select_one("SELECT location_id,qty_have FROM inventory_items WHERE id=#{stock_id}")
raise "Changed legacy stock" unless row["location_id"].to_i == root_id && BigDecimal(row["qty_have"].to_s) == BigDecimal("7.25")
raise "Changed legacy zero" unless connection.select_value("SELECT qty_have FROM inventory_items WHERE id=#{zero_id}") == 0
raise "Changed legacy location" unless connection.select_value("SELECT parent_id FROM locations WHERE id=#{root_id}").nil?
unknown_id = connection.insert("INSERT INTO inventory_items (name,user_id,location_id,shop_id,qty_have,unit,created_at,updated_at) VALUES ('migration unknown count',#{user_id},#{root_id},#{shop_id},NULL,'each',NOW(),NOW())")
begin
  quantity_migration.migrate(:down)
  raise "Rollback should have refused unknown counts"
rescue ActiveRecord::IrreversibleMigration
  raise "Unknown count changed" unless connection.select_value("SELECT qty_have FROM inventory_items WHERE id=#{unknown_id}").nil?
  puts "PASS: legacy positive/zero quantities and IDs preserved; unknown-count rollback refused without conversion"
ensure
  connection.execute("DELETE FROM inventory_items WHERE id=#{unknown_id}")
end
quantity_migration.migrate(:down)
quantity_migration.migrate(:up)
child_id = connection.insert("INSERT INTO locations (name,user_id,parent_id,hidden,created_at,updated_at) VALUES ('migration nested child',#{user_id},#{root_id},0,NOW(),NOW())")
begin
  migration.migrate(:down)
  raise "Rollback should have refused a populated hierarchy"
rescue ActiveRecord::IrreversibleMigration
  puts "PASS: stock-location association preserved; populated hierarchy rollback refused"
ensure
  connection.execute("DELETE FROM inventory_items WHERE id IN (#{stock_id},#{zero_id})")
  connection.execute("DELETE FROM locations WHERE id=#{child_id}")
  connection.execute("DELETE FROM locations WHERE id=#{root_id}")
  connection.execute("DELETE FROM shops WHERE id=#{shop_id}")
end
