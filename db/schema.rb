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

ActiveRecord::Schema[8.1].define(version: 2026_10_21_100001) do
  create_table "accounts", force: :cascade do |t|
    t.string "number", null: false
    t.string "holder_name", null: false
    t.string "status", null: false
    t.integer "balance", default: 0, null: false
    t.date "opened_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["number"], name: "index_accounts_on_number", unique: true
  end

  create_table "event_store_events", force: :cascade do |t|
    t.string "event_id", limit: 36, null: false
    t.string "event_type", null: false
    t.binary "metadata"
    t.binary "data", null: false
    t.datetime "created_at", null: false
    t.datetime "valid_at"
    t.index "COALESCE(valid_at, created_at)", name: "index_event_store_events_on_as_of"
    t.index ["created_at"], name: "index_event_store_events_on_created_at"
    t.index ["event_id"], name: "index_event_store_events_on_event_id", unique: true
    t.index ["event_type"], name: "index_event_store_events_on_event_type"
    t.index ["valid_at"], name: "index_event_store_events_on_valid_at"
  end

  create_table "event_store_events_in_streams", force: :cascade do |t|
    t.string "stream", null: false
    t.integer "position"
    t.string "event_id", limit: 36, null: false
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_event_store_events_in_streams_on_created_at"
    t.index ["event_id"], name: "index_event_store_events_in_streams_on_event_id"
    t.index ["stream", "event_id"], name: "index_event_store_events_in_streams_on_stream_and_event_id", unique: true
    t.index ["stream", "id"], name: "index_event_store_events_in_streams_on_stream_and_id"
    t.index ["stream", "position"], name: "index_event_store_events_in_streams_on_stream_and_position", unique: true
  end

  create_table "ledger_entries", force: :cascade do |t|
    t.string "account_number", null: false
    t.string "event_id", null: false
    t.string "kind", null: false
    t.integer "amount", null: false
    t.integer "balance_after", null: false
    t.string "memo"
    t.datetime "booked_at", null: false
    t.date "value_date", null: false
    t.string "actor"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "counterparty"
    t.string "transfer_id"
    t.index ["account_number"], name: "index_ledger_entries_on_account_number"
    t.index ["event_id"], name: "index_ledger_entries_on_event_id", unique: true
    t.index ["transfer_id"], name: "index_ledger_entries_on_transfer_id"
  end

  create_table "shop_order_lines", force: :cascade do |t|
    t.string "order_id", null: false
    t.string "sku", null: false
    t.string "name", null: false
    t.integer "unit_price", null: false
    t.integer "quantity", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_shop_order_lines_on_order_id"
  end

  create_table "shop_orders", force: :cascade do |t|
    t.string "order_id", null: false
    t.string "buyer_account", null: false
    t.integer "total", null: false
    t.string "status", null: false
    t.string "payment_transfer_id"
    t.string "refund_transfer_id"
    t.string "failure_reason"
    t.datetime "placed_at", null: false
    t.string "actor"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["buyer_account"], name: "index_shop_orders_on_buyer_account"
    t.index ["order_id"], name: "index_shop_orders_on_order_id", unique: true
    t.index ["payment_transfer_id"], name: "index_shop_orders_on_payment_transfer_id"
    t.index ["refund_transfer_id"], name: "index_shop_orders_on_refund_transfer_id"
  end

  create_table "shop_products", force: :cascade do |t|
    t.string "sku", null: false
    t.string "name", null: false
    t.string "emoji"
    t.integer "price", null: false
    t.integer "stock", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sku"], name: "index_shop_products_on_sku", unique: true
  end

  create_table "transfers", force: :cascade do |t|
    t.string "transfer_id", null: false
    t.string "from_account", null: false
    t.string "to_account", null: false
    t.integer "amount", null: false
    t.string "memo"
    t.string "status", null: false
    t.string "failure_reason"
    t.datetime "requested_at", null: false
    t.datetime "settled_at"
    t.string "actor"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["from_account"], name: "index_transfers_on_from_account"
    t.index ["to_account"], name: "index_transfers_on_to_account"
    t.index ["transfer_id"], name: "index_transfers_on_transfer_id", unique: true
  end

  add_foreign_key "event_store_events_in_streams", "event_store_events", column: "event_id", primary_key: "event_id"
end
