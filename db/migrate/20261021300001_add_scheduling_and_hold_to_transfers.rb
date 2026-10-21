# 振込の差し止め（TODO の Q3）: 予約振込の実行日、高額振込の保留、実行前の取消・差し止め
class AddSchedulingAndHoldToTransfers < ActiveRecord::Migration[8.1]
  def change
    change_table :transfers, bulk: true do |t|
      t.date :execute_on          # 予約振込の実行日（すぐの振込は nil）
      t.datetime :held_at         # 高額で保留になった時刻
      t.datetime :released_at     # 行員が「通す」した時刻
      t.datetime :cancelled_at    # 取消（利用者）・差し止め（行員）の時刻
      t.string :cancel_reason
      t.string :cancelled_by      # 取消・差し止めした人（イベントの actor）
    end
    add_index :transfers, %i[status execute_on]
  end
end
