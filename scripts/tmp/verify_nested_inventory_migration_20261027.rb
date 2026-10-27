# Verify only the disposable database, never the configured live application DB.
connection = ActiveRecord::Base.connection
raise "Wrong database" unless connection.current_database == "wayfinder_api_test_nested_20261027"
require Rails.root.join("db/migrate/20261027000000_add_location_hierarchy")
raise "Unexpected hierarchy" unless connection.select_value("SELECT COUNT(*) FROM locations WHERE parent_id IS NOT NULL").to_i.zero?
migration = AddLocationHierarchy.new
migration.migrate(:down)
user_id = connection.select_value("SELECT id FROM users LIMIT 1").to_i
raise "Missing fixture owner" unless user_id.positive?
root_id = connection.insert("INSERT INTO locations (name,user_id,hidden,created_at,updated_at) VALUES ('migration preserved root',#{user_id},0,NOW(),NOW())")
shop_id = connection.insert("INSERT INTO shops (name,user_id,hidden,created_at,updated_at) VALUES ('migration test supplier',#{user_id},0,NOW(),NOW())")
stock_id = connection.insert("INSERT INTO inventory_items (name,user_id,location_id,shop_id,qty_have,unit,created_at,updated_at) VALUES ('migration preserved stock',#{user_id},#{root_id},#{shop_id},7.25,'each',NOW(),NOW())")
migration.migrate(:up)
row = connection.select_one("SELECT location_id,qty_have FROM inventory_items WHERE id=#{stock_id}")
raise "Changed legacy stock" unless row["location_id"].to_i == root_id && BigDecimal(row["qty_have"].to_s) == BigDecimal("7.25")
raise "Changed legacy location" unless connection.select_value("SELECT parent_id FROM locations WHERE id=#{root_id}").nil?
child_id = connection.insert("INSERT INTO locations (name,user_id,parent_id,hidden,created_at,updated_at) VALUES ('migration nested child',#{user_id},#{root_id},0,NOW(),NOW())")
begin
  migration.migrate(:down)
  raise "Rollback should have refused a populated hierarchy"
rescue ActiveRecord::IrreversibleMigration
  puts "PASS: existing IDs, quantity and stock-location association preserved; populated hierarchy rollback refused"
ensure
  connection.execute("DELETE FROM inventory_items WHERE id=#{stock_id}")
  connection.execute("DELETE FROM locations WHERE id IN (#{child_id})")
  connection.execute("DELETE FROM locations WHERE id=#{root_id}")
  connection.execute("DELETE FROM shops WHERE id=#{shop_id}")
end
