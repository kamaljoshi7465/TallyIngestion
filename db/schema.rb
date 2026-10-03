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

ActiveRecord::Schema[8.0].define(version: 2026_10_03_103927) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounting_allocations", force: :cascade do |t|
    t.bigint "inventory_entry_id", null: false
    t.integer "position", null: false
    t.string "ledger_name"
    t.string "is_deemed_positive"
    t.string "amount"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inventory_entry_id", "position"], name: "idx_on_inventory_entry_id_position_4976eb7f34"
    t.index ["inventory_entry_id"], name: "index_accounting_allocations_on_inventory_entry_id"
  end

  create_table "bank_allocations", force: :cascade do |t|
    t.bigint "ledger_entry_id", null: false
    t.integer "position", null: false
    t.string "date"
    t.string "name"
    t.string "transaction_type"
    t.string "amount"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ledger_entry_id", "position"], name: "index_bank_allocations_on_ledger_entry_id_and_position"
    t.index ["ledger_entry_id"], name: "index_bank_allocations_on_ledger_entry_id"
  end

  create_table "batch_allocations", force: :cascade do |t|
    t.bigint "inventory_entry_id", null: false
    t.integer "position", null: false
    t.string "godown_name"
    t.string "batch_name"
    t.string "actual_qty"
    t.string "billed_qty"
    t.string "amount"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inventory_entry_id", "position"], name: "index_batch_allocations_on_inventory_entry_id_and_position"
    t.index ["inventory_entry_id"], name: "index_batch_allocations_on_inventory_entry_id"
  end

  create_table "bill_allocations", force: :cascade do |t|
    t.bigint "ledger_entry_id", null: false
    t.integer "position", null: false
    t.string "name"
    t.string "bill_type"
    t.string "amount"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ledger_entry_id", "position"], name: "index_bill_allocations_on_ledger_entry_id_and_position"
    t.index ["ledger_entry_id"], name: "index_bill_allocations_on_ledger_entry_id"
  end

  create_table "imports", force: :cascade do |t|
    t.string "content_hash", null: false
    t.string "document_type", null: false
    t.string "status", null: false
    t.string "detected_encoding"
    t.jsonb "warnings", default: []
    t.jsonb "error_messages", default: []
    t.text "raw_source"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "tally_response"
    t.index ["content_hash"], name: "index_imports_on_content_hash", unique: true
  end

  create_table "inventory_entries", force: :cascade do |t|
    t.bigint "voucher_id", null: false
    t.integer "position", null: false
    t.string "source_tag", null: false
    t.string "stock_item_name"
    t.string "is_deemed_positive"
    t.string "actual_qty"
    t.string "billed_qty"
    t.string "rate"
    t.string "amount"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["voucher_id", "position"], name: "index_inventory_entries_on_voucher_id_and_position"
    t.index ["voucher_id"], name: "index_inventory_entries_on_voucher_id"
  end

  create_table "ledger_entries", force: :cascade do |t|
    t.bigint "voucher_id", null: false
    t.integer "position", null: false
    t.string "source_tag", null: false
    t.string "ledger_name"
    t.string "is_deemed_positive"
    t.string "amount"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["voucher_id"], name: "index_ledger_entries_on_voucher_id"
  end

  create_table "rate_details", force: :cascade do |t|
    t.string "rateable_type", null: false
    t.bigint "rateable_id", null: false
    t.integer "position", null: false
    t.string "duty_head"
    t.string "rate"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["rateable_type", "rateable_id", "position"], name: "index_rate_details_on_rateable_and_position"
    t.index ["rateable_type", "rateable_id"], name: "index_rate_details_on_rateable"
  end

  create_table "vouchers", force: :cascade do |t|
    t.bigint "import_id", null: false
    t.integer "voucher_index", null: false
    t.string "date"
    t.string "voucher_type"
    t.string "voucher_number"
    t.string "party_ledger_name"
    t.text "narration"
    t.jsonb "xml_attributes", default: {}
    t.jsonb "warnings", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["import_id"], name: "index_vouchers_on_import_id"
  end

  add_foreign_key "accounting_allocations", "inventory_entries"
  add_foreign_key "bank_allocations", "ledger_entries"
  add_foreign_key "batch_allocations", "inventory_entries"
  add_foreign_key "bill_allocations", "ledger_entries"
  add_foreign_key "inventory_entries", "vouchers"
  add_foreign_key "ledger_entries", "vouchers"
  add_foreign_key "vouchers", "imports"
end
