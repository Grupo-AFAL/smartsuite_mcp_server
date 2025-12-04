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

ActiveRecord::Schema[8.0].define(version: 2025_12_04_175034) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "api_calls", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "tool_name", null: false
    t.string "solution_id"
    t.string "table_id"
    t.boolean "cache_hit", default: false
    t.integer "duration_ms"
    t.datetime "created_at", null: false
    t.index ["user_id", "created_at"], name: "index_api_calls_on_user_id_and_created_at"
    t.index ["user_id", "tool_name"], name: "index_api_calls_on_user_id_and_tool_name"
    t.index ["user_id"], name: "index_api_calls_on_user_id"
  end

  create_table "api_keys", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token", null: false
    t.string "name"
    t.datetime "last_used_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_api_keys_on_token", unique: true
    t.index ["user_id"], name: "index_api_keys_on_user_id"
  end

  create_table "cache_members", primary_key: "member_id", id: :string, force: :cascade do |t|
    t.jsonb "data", default: {}, null: false
    t.datetime "cached_at", null: false
    t.datetime "expires_at", null: false
    t.index ["expires_at"], name: "index_cache_members_on_expires_at"
  end

  create_table "cache_metadata", primary_key: "table_id", id: :string, force: :cascade do |t|
    t.string "pg_table_name", null: false
    t.jsonb "schema", default: {}
    t.integer "record_count", default: 0
    t.integer "ttl_seconds", default: 14400
    t.datetime "cached_at"
    t.datetime "expires_at"
  end

  create_table "cache_records", id: false, force: :cascade do |t|
    t.string "table_id", null: false
    t.string "record_id", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "cached_at", null: false
    t.datetime "expires_at", null: false
    t.index ["data"], name: "idx_cache_records_data", using: :gin
    t.index ["expires_at"], name: "index_cache_records_on_expires_at"
    t.index ["table_id", "expires_at"], name: "index_cache_records_on_table_id_and_expires_at"
    t.index ["table_id", "record_id"], name: "index_cache_records_on_table_id_and_record_id", unique: true
  end

  create_table "cache_solutions", primary_key: "solution_id", id: :string, force: :cascade do |t|
    t.jsonb "data", default: {}, null: false
    t.datetime "cached_at", null: false
    t.datetime "expires_at", null: false
    t.index ["expires_at"], name: "index_cache_solutions_on_expires_at"
  end

  create_table "cache_table_schemas", primary_key: "table_id", id: :string, force: :cascade do |t|
    t.jsonb "structure", default: {}, null: false
    t.datetime "cached_at", null: false
    t.datetime "expires_at", null: false
  end

  create_table "cache_tables", primary_key: "table_id", id: :string, force: :cascade do |t|
    t.string "solution_id"
    t.jsonb "data", default: {}, null: false
    t.datetime "cached_at", null: false
    t.datetime "expires_at", null: false
    t.index ["expires_at"], name: "index_cache_tables_on_expires_at"
    t.index ["solution_id"], name: "index_cache_tables_on_solution_id"
  end

  create_table "cache_teams", primary_key: "team_id", id: :string, force: :cascade do |t|
    t.jsonb "data", default: {}, null: false
    t.datetime "cached_at", null: false
    t.datetime "expires_at", null: false
    t.index ["expires_at"], name: "index_cache_teams_on_expires_at"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "smartsuite_api_key", null: false
    t.string "smartsuite_account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "api_calls", "users"
  add_foreign_key "api_keys", "users"
end
