# 読み取りモデル: 通帳の明細（1イベント = 1行）。正はイベントストア。
class CreateLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :ledger_entries do |t|
      t.string :account_number, null: false
      t.string :event_id, null: false
      t.string :kind, null: false
      t.integer :amount, null: false          # 入金は正、出金は負
      t.integer :balance_after, null: false   # 記帳順で見たときの残高
      t.string :memo
      t.datetime :booked_at, null: false      # 記帳日時（RES の timestamp）
      t.date :value_date, null: false         # 起算日（RES の valid_at）
      t.string :actor                         # web / mcp / console など

      t.timestamps
    end
    add_index :ledger_entries, :account_number
    add_index :ledger_entries, :event_id, unique: true
  end
end
