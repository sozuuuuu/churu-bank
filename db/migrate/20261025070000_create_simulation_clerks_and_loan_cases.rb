# ねこ町の行員エージェント（窓口のたま・係長のくろ）。お金の正はイベントストア。ここは画面と、審査・督促の町の記録
class CreateSimulationClerksAndLoanCases < ActiveRecord::Migration[8.1]
  def change
    # 行員ごとの様子（画面に出すもの）。行員の Ractor が役場へ出した Report を、役場（メインの Ractor）が書く
    create_table :simulation_clerks do |t|
      t.string :name, null: false
      t.references :staff, null: false, foreign_key: true
      t.string :role, null: false            # teller（窓口）/ chief（係長）
      t.string :state
      t.string :last_action
      t.datetime :last_action_at
      t.integer :handled, null: false, default: 0  # 見た申込の数
      t.integer :approved, null: false, default: 0
      t.integer :rejected, null: false, default: 0
      t.integer :forwarded, null: false, default: 0 # 係長へ回した数
      t.integer :dunned, null: false, default: 0    # 督促状の数
      t.integer :restarts, null: false, default: 0
      t.string :last_error
      t.timestamps
      t.index :name, unique: true
    end

    # ちゅ〜るローンの申込と、その後（審査・決裁・督促）。銀行の貸付（Loan）は承認されてから作る
    create_table :simulation_loan_cases do |t|
      t.string :resident, null: false
      t.integer :amount, null: false
      t.string :status, null: false        # applied / forwarded / approved / rejected / withdrawn
      t.string :handled_by                 # 審査した行員
      t.string :decided_by                 # 決めた行員
      t.string :reason
      t.string :loan_id                    # 承認して貸したときの貸付
      t.integer :day                       # 申し込んだ日（町の何日目か）
      t.integer :decided_day
      t.integer :last_repaid_day
      t.integer :last_dunned_day
      t.timestamps
      t.index %i[resident status]
    end
  end
end
