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

ActiveRecord::Schema[8.0].define(version: 2026_08_20_181417) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "api_keys", force: :cascade do |t|
    t.string "token_digest", null: false
    t.string "label", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_keys_on_user_id"
  end

  create_table "artifacts", force: :cascade do |t|
    t.string "slug", null: false
    t.bigint "api_key_id", null: false
    t.string "storage_key", null: false
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key_id"], name: "index_artifacts_on_api_key_id"
    t.index ["slug"], name: "index_artifacts_on_slug", unique: true
  end

  create_table "organization_invites", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "email"], name: "index_organization_invites_on_organization_id_and_email", unique: true
    t.index ["organization_id"], name: "index_organization_invites_on_organization_id"
  end

  create_table "organization_memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "organization_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_organization_memberships_on_organization_id"
    t.index ["user_id", "organization_id"], name: "index_organization_memberships_on_user_id_and_organization_id", unique: true
    t.index ["user_id"], name: "index_organization_memberships_on_user_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "api_keys", "users"
  add_foreign_key "artifacts", "api_keys"
  add_foreign_key "organization_invites", "organizations"
  add_foreign_key "organization_memberships", "organizations"
  add_foreign_key "organization_memberships", "users"
end
