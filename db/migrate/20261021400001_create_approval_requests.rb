# 二人承認（TODO の Q2）の読み取りモデル。正はイベントストアの Approval$<申請ID>
class CreateApprovalRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :approval_requests do |t|
      t.string :approval_id, null: false, index: { unique: true }
      t.string :kind, null: false             # reversal / transfer_reversal / unfreeze
      t.string :account_number, index: true   # 対象の口座（組戻しは振込元）
      t.string :ledger_event_id               # 取り消す通帳の行（reversal）
      t.string :transfer_id                   # 組戻しする振込（transfer_reversal）
      t.string :target_key, null: false       # 同じ対象の承認待ちを1つにする
      t.string :summary, null: false
      t.string :reason, null: false
      t.string :status, null: false, index: true
      t.string :requested_by, null: false
      t.datetime :requested_at, null: false
      t.string :decided_by                    # 承認・却下した行員（取り下げは本人）
      t.datetime :decided_at
      t.datetime :executed_at
      t.string :reject_reason
    end
    add_index :approval_requests, :target_key, unique: true, where: "status = 'pending'",
                                               name: "index_approval_requests_pending_target"
  end
end
