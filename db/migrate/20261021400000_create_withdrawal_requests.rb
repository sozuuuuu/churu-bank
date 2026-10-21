# 出金依頼（窓口取引、TODO の Q1）の読み取りモデル。正はイベントストアの WithdrawalRequest$<依頼ID>
class CreateWithdrawalRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :withdrawal_requests do |t|
      t.string :request_id, null: false, index: { unique: true }
      t.string :account_number, null: false, index: true
      t.integer :amount, null: false
      t.string :memo
      t.string :status, null: false, index: true
      t.datetime :requested_at, null: false
      t.string :requested_by
      t.datetime :closed_at
      t.string :closed_by
      t.string :reject_reason
      t.string :withdrawal_event_id
    end
  end
end
