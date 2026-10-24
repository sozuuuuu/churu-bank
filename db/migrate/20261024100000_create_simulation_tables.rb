# ねこ町の住民の暮らし（packs/simulation、TODO の K）。お金の正はイベントストア。ここは画面と、町を動かす係のための表
class CreateSimulationTables < ActiveRecord::Migration[8.1]
  def change
    # 町の動かし方（1行だけ）。画面が running と seconds_per_day を書き、町を動かす係（bin/rails churu:simulate）が読む。
    # 係は動いているあいだ heartbeat_at を書き直し、town_running（ほんとうに動いているか）・day・time を書く
    create_table :simulation_controls do |t|
      t.boolean :running, null: false, default: false   # 画面で「動かす」を押したか
      t.integer :seconds_per_day, null: false, default: 24
      t.boolean :town_running, null: false, default: false
      t.integer :day, null: false, default: 0           # 時計が最後に知らせた日（次に動かすときは、この次の日から）
      t.string :time                                    # morning / noon / evening / night
      t.datetime :heartbeat_at
      t.string :employer_account                        # 給料を払う口座（ねこ町のしごと場）
      t.timestamps
    end

    # 住民ごとの様子（画面に出すもの）。住民の Ractor が役場へ出した Report を、役場（メインの Ractor）が書く
    create_table :simulation_residents do |t|
      t.string :name, null: false
      t.references :customer, null: false, foreign_key: true # 住民は顧客台帳の利用者（ログインして暮らしぶりも見られる）
      t.string :account_number, null: false
      t.string :temperament, null: false
      t.string :state
      t.integer :mood
      t.integer :money                                        # 住民の記憶の中の「所持金の見込み」
      t.string :last_action
      t.datetime :last_action_at
      t.integer :restarts, null: false, default: 0           # 見張り役が起こし直した回数（町を動かすたびに 0 から）
      t.string :last_error                                    # 最後に倒れたわけ
      t.integer :paid_day                                     # 最後に給料を払った日（同じ日に2回払わない）
      t.timestamps
      t.index :name, unique: true
    end
  end
end
