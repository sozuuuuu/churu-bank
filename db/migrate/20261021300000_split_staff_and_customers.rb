# Q0: 行員と利用者を別のテーブルに分ける（users の admin フラグをやめる）。
#   users（admin = true）  → staffs（行員。packs/staff_identity）
#   users（admin = false） → customers（利用者。packs/customer_registry）。id はそのまま引き継ぐ
#   sessions               → staff_sessions / customer_sessions（ログインし直してもらうので中身は移さない）
#   account_ownerships・notice_targets・notice_receipts の user_id → customer_id（行員の分は捨てる）
# イベントの metadata の actor（admin:<メール> など）は書き換えない（過去の記録なので）
class SplitStaffAndCustomers < ActiveRecord::Migration[8.1]
  def up
    create_table :staffs do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :name, null: false
      t.timestamps
      t.index :email_address, unique: true
    end

    create_table :staff_sessions do |t|
      t.references :staff, null: false, foreign_key: { on_delete: :cascade }
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end

    create_table :customers do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :name, null: false
      t.timestamps
      t.index :email_address, unique: true
    end

    create_table :customer_sessions do |t|
      t.references :customer, null: false, foreign_key: { on_delete: :cascade }
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end

    columns = "id, email_address, password_digest, name, created_at, updated_at"
    execute "INSERT INTO staffs (#{columns}) SELECT #{columns} FROM users WHERE admin = 1"
    execute "INSERT INTO customers (#{columns}) SELECT #{columns} FROM users WHERE admin = 0"

    %i[account_ownerships notice_targets notice_receipts].each do |table|
      execute "DELETE FROM #{table} WHERE user_id NOT IN (SELECT id FROM customers)"
      remove_foreign_key table, :users
      rename_column table, :user_id, :customer_id # インデックスの名前も customer_id に変わる
      add_foreign_key table, :customers
    end

    drop_table :sessions
    drop_table :users
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
