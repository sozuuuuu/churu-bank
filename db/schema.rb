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

ActiveRecord::Schema[8.1].define(version: 2026_10_25_070000) do
  create_table "account_ownerships", force: :cascade do |t|
    t.integer "customer_id", null: false
    t.string "account_number", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_number"], name: "index_account_ownerships_on_account_number"
    t.index ["customer_id", "account_number"], name: "index_account_ownerships_on_customer_id_and_account_number", unique: true
    t.index ["customer_id"], name: "index_account_ownerships_on_customer_id"
  end

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

  create_table "approval_requests", force: :cascade do |t|
    t.string "approval_id", null: false
    t.string "kind", null: false
    t.string "account_number"
    t.string "ledger_event_id"
    t.string "transfer_id"
    t.string "target_key", null: false
    t.string "summary", null: false
    t.string "reason", null: false
    t.string "status", null: false
    t.string "requested_by", null: false
    t.datetime "requested_at", null: false
    t.string "decided_by"
    t.datetime "decided_at"
    t.datetime "executed_at"
    t.string "reject_reason"
    t.index ["account_number"], name: "index_approval_requests_on_account_number"
    t.index ["approval_id"], name: "index_approval_requests_on_approval_id", unique: true
    t.index ["status"], name: "index_approval_requests_on_status"
    t.index ["target_key"], name: "index_approval_requests_pending_target", unique: true, where: "status = 'pending'"
  end

  create_table "counter_messages", force: :cascade do |t|
    t.integer "counter_ticket_id", null: false
    t.string "author_role", null: false
    t.integer "author_id", null: false
    t.string "author_name", null: false
    t.string "kind", default: "text", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.index ["counter_ticket_id"], name: "index_counter_messages_on_counter_ticket_id"
  end

  create_table "counter_presences", force: :cascade do |t|
    t.string "room", null: false
    t.string "role", null: false
    t.integer "person_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.index ["room", "role"], name: "index_counter_presences_on_room_and_role"
  end

  create_table "counter_tickets", force: :cascade do |t|
    t.date "service_date", null: false
    t.integer "number", null: false
    t.integer "customer_id", null: false
    t.string "status", default: "waiting", null: false
    t.datetime "taken_at", null: false
    t.datetime "called_at"
    t.integer "staff_id"
    t.string "staff_name"
    t.datetime "closed_at"
    t.string "closed_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_counter_tickets_on_customer_id"
    t.index ["customer_id"], name: "index_counter_tickets_one_active_per_customer", unique: true, where: "status IN ('waiting', 'called')"
    t.index ["service_date", "number"], name: "index_counter_tickets_on_service_date_and_number", unique: true
    t.index ["staff_id"], name: "index_counter_tickets_on_staff_id"
    t.index ["status"], name: "index_counter_tickets_on_status"
  end

  create_table "customer_sessions", force: :cascade do |t|
    t.integer "customer_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_customer_sessions_on_customer_id"
  end

  create_table "customers", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_customers_on_email_address", unique: true
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
    t.string "reversal_of"
    t.string "reversed_by"
    t.index ["account_number"], name: "index_ledger_entries_on_account_number"
    t.index ["event_id"], name: "index_ledger_entries_on_event_id", unique: true
    t.index ["reversal_of"], name: "index_ledger_entries_on_reversal_of"
    t.index ["transfer_id"], name: "index_ledger_entries_on_transfer_id"
  end

  create_table "loans", force: :cascade do |t|
    t.string "loan_id", null: false
    t.string "account_number", null: false
    t.integer "principal", null: false
    t.integer "fee", null: false
    t.integer "outstanding", null: false
    t.string "status", null: false
    t.string "memo"
    t.datetime "granted_at", null: false
    t.datetime "settled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_number", "status"], name: "index_loans_on_account_number_and_status"
    t.index ["loan_id"], name: "index_loans_on_loan_id", unique: true
  end

  create_table "notice_receipts", force: :cascade do |t|
    t.integer "notice_id", null: false
    t.integer "customer_id", null: false
    t.datetime "read_at"
    t.datetime "dismissed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_notice_receipts_on_customer_id"
    t.index ["notice_id", "customer_id"], name: "index_notice_receipts_on_notice_id_and_customer_id", unique: true
    t.index ["notice_id"], name: "index_notice_receipts_on_notice_id"
  end

  create_table "notice_targets", force: :cascade do |t|
    t.integer "notice_id", null: false
    t.integer "customer_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_notice_targets_on_customer_id"
    t.index ["notice_id", "customer_id"], name: "index_notice_targets_on_notice_id_and_customer_id", unique: true
    t.index ["notice_id"], name: "index_notice_targets_on_notice_id"
  end

  create_table "notices", force: :cascade do |t|
    t.string "kind", null: false
    t.string "title", null: false
    t.text "body", default: "", null: false
    t.boolean "important", default: false, null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at"
    t.string "audience", default: "everyone", null: false
    t.string "posted_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["starts_at", "ends_at"], name: "index_notices_on_starts_at_and_ends_at"
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

  create_table "simulation_clerks", force: :cascade do |t|
    t.string "name", null: false
    t.integer "staff_id", null: false
    t.string "role", null: false
    t.string "state"
    t.string "last_action"
    t.datetime "last_action_at"
    t.integer "handled", default: 0, null: false
    t.integer "approved", default: 0, null: false
    t.integer "rejected", default: 0, null: false
    t.integer "forwarded", default: 0, null: false
    t.integer "dunned", default: 0, null: false
    t.integer "restarts", default: 0, null: false
    t.string "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_simulation_clerks_on_name", unique: true
    t.index ["staff_id"], name: "index_simulation_clerks_on_staff_id"
  end

  create_table "simulation_controls", force: :cascade do |t|
    t.boolean "running", default: false, null: false
    t.integer "seconds_per_day", default: 24, null: false
    t.boolean "town_running", default: false, null: false
    t.integer "day", default: 0, null: false
    t.string "time"
    t.datetime "heartbeat_at"
    t.string "employer_account"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "landlord_account"
    t.json "places"
  end

  create_table "simulation_debts", force: :cascade do |t|
    t.string "lender", null: false
    t.string "borrower", null: false
    t.integer "amount", null: false
    t.integer "repaid", default: 0, null: false
    t.integer "day"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["borrower", "lender"], name: "index_simulation_debts_on_borrower_and_lender"
  end

  create_table "simulation_letters", force: :cascade do |t|
    t.string "sender", null: false
    t.string "recipient", null: false
    t.string "kind", null: false
    t.string "text", null: false
    t.integer "day"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "simulation_loan_cases", force: :cascade do |t|
    t.string "resident", null: false
    t.integer "amount", null: false
    t.string "status", null: false
    t.string "handled_by"
    t.string "decided_by"
    t.string "reason"
    t.string "loan_id"
    t.integer "day"
    t.integer "decided_day"
    t.integer "last_repaid_day"
    t.integer "last_dunned_day"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["resident", "status"], name: "index_simulation_loan_cases_on_resident_and_status"
  end

  create_table "simulation_residents", force: :cascade do |t|
    t.string "name", null: false
    t.integer "customer_id", null: false
    t.string "account_number", null: false
    t.string "temperament", null: false
    t.string "state"
    t.integer "mood"
    t.integer "money"
    t.string "last_action"
    t.datetime "last_action_at"
    t.integer "restarts", default: 0, null: false
    t.string "last_error"
    t.integer "paid_day"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "letters_received", default: 0, null: false
    t.integer "letters_sent", default: 0, null: false
    t.integer "rent_paid_day"
    t.index ["customer_id"], name: "index_simulation_residents_on_customer_id"
    t.index ["name"], name: "index_simulation_residents_on_name", unique: true
  end

  create_table "staff_sessions", force: :cascade do |t|
    t.integer "staff_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["staff_id"], name: "index_staff_sessions_on_staff_id"
  end

  create_table "staffs", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_staffs_on_email_address", unique: true
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
    t.datetime "reversed_at"
    t.string "reversal_reason"
    t.date "execute_on"
    t.datetime "held_at"
    t.datetime "released_at"
    t.datetime "cancelled_at"
    t.string "cancel_reason"
    t.string "cancelled_by"
    t.index ["from_account"], name: "index_transfers_on_from_account"
    t.index ["status", "execute_on"], name: "index_transfers_on_status_and_execute_on"
    t.index ["to_account"], name: "index_transfers_on_to_account"
    t.index ["transfer_id"], name: "index_transfers_on_transfer_id", unique: true
  end

  create_table "withdrawal_requests", force: :cascade do |t|
    t.string "request_id", null: false
    t.string "account_number", null: false
    t.integer "amount", null: false
    t.string "memo"
    t.string "status", null: false
    t.datetime "requested_at", null: false
    t.string "requested_by"
    t.datetime "closed_at"
    t.string "closed_by"
    t.string "reject_reason"
    t.string "withdrawal_event_id"
    t.index ["account_number"], name: "index_withdrawal_requests_on_account_number"
    t.index ["request_id"], name: "index_withdrawal_requests_on_request_id", unique: true
    t.index ["status"], name: "index_withdrawal_requests_on_status"
  end

  add_foreign_key "account_ownerships", "customers"
  add_foreign_key "counter_messages", "counter_tickets"
  add_foreign_key "counter_tickets", "customers"
  add_foreign_key "counter_tickets", "staffs"
  add_foreign_key "customer_sessions", "customers", on_delete: :cascade
  add_foreign_key "event_store_events_in_streams", "event_store_events", column: "event_id", primary_key: "event_id"
  add_foreign_key "notice_receipts", "customers"
  add_foreign_key "notice_receipts", "notices"
  add_foreign_key "notice_targets", "customers"
  add_foreign_key "notice_targets", "notices"
  add_foreign_key "simulation_clerks", "staffs"
  add_foreign_key "simulation_residents", "customers"
  add_foreign_key "staff_sessions", "staffs", on_delete: :cascade
end
