# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_06_08_000001) do
  create_table "categories", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "name"], name: "idx_categories_user_name", unique: true
    t.index ["user_id"], name: "index_categories_on_user_id"
  end

  create_table "inventory_items", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.decimal "qty_have", precision: 10, scale: 2, default: "0.0", null: false
    t.string "unit", default: "", null: false
    t.bigint "location_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "shop_id"
    t.bigint "user_id", null: false
    t.index ["location_id"], name: "index_inventory_items_on_location_id"
    t.index ["shop_id"], name: "index_inventory_items_on_shop_id"
    t.index ["user_id", "name", "location_id"], name: "idx_inventory_items_user_name_location", unique: true
    t.index ["user_id"], name: "index_inventory_items_on_user_id"
  end

  create_table "item_blocks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "blocker_id", null: false
    t.bigint "blocked_id", null: false
    t.bigint "user_id", null: false
    t.index ["blocked_id"], name: "index_item_blocks_on_blocked_id"
    t.index ["blocker_id", "blocked_id"], name: "index_item_blocks_on_blocker_id_and_blocked_id", unique: true
    t.index ["user_id"], name: "index_item_blocks_on_user_id"
  end

  create_table "item_inventories", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "item_id", null: false
    t.bigint "inventory_item_id", null: false
    t.decimal "qty_reserved", precision: 10, scale: 2, default: "0.0", null: false
    t.string "unit", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["inventory_item_id"], name: "index_item_inventories_on_inventory_item_id"
    t.index ["item_id", "inventory_item_id"], name: "index_item_inventories_on_item_id_and_inventory_item_id", unique: true
    t.index ["item_id"], name: "index_item_inventories_on_item_id"
    t.index ["user_id"], name: "index_item_inventories_on_user_id"
  end

  create_table "items", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "title", null: false
    t.text "notes"
    t.bigint "category_id", null: false
    t.bigint "mood_id", null: false
    t.bigint "parent_id"
    t.integer "personal_impact", default: 0, null: false
    t.integer "emotional_impact", default: 0, null: false
    t.integer "family_impact", default: 0, null: false
    t.integer "time_estimate_minutes", default: 0, null: false
    t.integer "cost_cents", default: 0, null: false
    t.date "deadline"
    t.boolean "done", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "recurrence_kind", default: 0, null: false
    t.integer "recurrence_unit", default: 0, null: false
    t.integer "recurrence_interval", default: 1, null: false
    t.integer "recurrence_day_of_month"
    t.integer "recurrence_month_of_year"
    t.date "recurrence_start_on"
    t.datetime "completed_at"
    t.bigint "user_id", null: false
    t.index ["category_id"], name: "index_items_on_category_id"
    t.index ["deadline"], name: "index_items_on_deadline"
    t.index ["done"], name: "index_items_on_done"
    t.index ["mood_id"], name: "index_items_on_mood_id"
    t.index ["parent_id"], name: "index_items_on_parent_id"
    t.index ["recurrence_day_of_month", "recurrence_month_of_year"], name: "idx_on_recurrence_day_of_month_recurrence_month_of__a778ad1e01"
    t.index ["recurrence_kind"], name: "index_items_on_recurrence_kind"
    t.index ["recurrence_unit", "recurrence_interval"], name: "index_items_on_recurrence_unit_and_recurrence_interval"
    t.index ["time_estimate_minutes"], name: "index_items_on_time_estimate_minutes"
    t.index ["user_id"], name: "index_items_on_user_id"
  end

  create_table "locations", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "name"], name: "idx_locations_user_name", unique: true
    t.index ["user_id"], name: "index_locations_on_user_id"
  end

  create_table "material_requirements", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "item_id", null: false
    t.string "name", null: false
    t.decimal "qty_needed", precision: 10, scale: 2, default: "1.0", null: false
    t.string "unit", default: "", null: false
    t.bigint "shop_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["item_id", "name"], name: "index_material_requirements_on_item_id_and_name", unique: true
    t.index ["item_id"], name: "index_material_requirements_on_item_id"
    t.index ["shop_id"], name: "index_material_requirements_on_shop_id"
    t.index ["user_id"], name: "index_material_requirements_on_user_id"
  end

  create_table "moods", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "name"], name: "idx_moods_user_name", unique: true
    t.index ["user_id"], name: "index_moods_on_user_id"
  end

  create_table "schedule_entries", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.date "on_date", null: false
    t.integer "day_part", default: 0, null: false
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["category_id"], name: "index_schedule_entries_on_category_id"
    t.index ["on_date", "day_part", "category_id"], name: "idx_schedule_entries_unique_slot", unique: true
    t.index ["on_date", "day_part"], name: "index_schedule_entries_on_on_date_and_day_part"
    t.index ["user_id"], name: "index_schedule_entries_on_user_id"
  end

  create_table "shops", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "name"], name: "idx_shops_user_name", unique: true
    t.index ["user_id"], name: "index_shops_on_user_id"
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "access_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["access_key"], name: "index_users_on_access_key", unique: true
  end

  add_foreign_key "categories", "users"
  add_foreign_key "inventory_items", "locations"
  add_foreign_key "inventory_items", "shops"
  add_foreign_key "inventory_items", "users"
  add_foreign_key "item_blocks", "items", column: "blocked_id", on_delete: :cascade
  add_foreign_key "item_blocks", "items", column: "blocker_id", on_delete: :cascade
  add_foreign_key "item_blocks", "users"
  add_foreign_key "item_inventories", "inventory_items"
  add_foreign_key "item_inventories", "items"
  add_foreign_key "item_inventories", "users"
  add_foreign_key "items", "categories"
  add_foreign_key "items", "items", column: "parent_id", on_delete: :nullify
  add_foreign_key "items", "moods"
  add_foreign_key "items", "users"
  add_foreign_key "locations", "users"
  add_foreign_key "material_requirements", "items", on_delete: :cascade
  add_foreign_key "material_requirements", "shops"
  add_foreign_key "material_requirements", "users"
  add_foreign_key "moods", "users"
  add_foreign_key "schedule_entries", "categories"
  add_foreign_key "schedule_entries", "users"
  add_foreign_key "shops", "users"
end
