# 読み取りモデル: 振込の一覧と状態。正はイベントストア（Transfer$<振込ID> ストリーム）。
class CreateTransfers < ActiveRecord::Migration[8.1]
  def change
    create_table :transfers do |t|
      t.string :transfer_id, null: false
      t.string :from_account, null: false
      t.string :to_account, null: false
      t.integer :amount, null: false
      t.string :memo
      t.string :status, null: false        # requested / completed / failed
      t.string :failure_reason
      t.datetime :requested_at, null: false
      t.datetime :settled_at
      t.string :actor

      t.timestamps
    end
    add_index :transfers, :transfer_id, unique: true
    add_index :transfers, :from_account
    add_index :transfers, :to_account
  end
end
