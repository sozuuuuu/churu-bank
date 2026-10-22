# 窓口の整理券と窓口チャット（packs/counter、TODO の S）。イベントソーシングにはしない（README の「窓口の整理券と窓口チャット」の節）
class CreateCounterTickets < ActiveRecord::Migration[8.1]
  def change
    # 番号札。番号は日ごとに 1 から。消さずに状態と時刻を残す（だれがいつ取り、だれがいつ呼び、いつ終わったか）
    create_table :counter_tickets do |t|
      t.date :service_date, null: false
      t.integer :number, null: false
      t.references :customer, null: false, foreign_key: true
      t.string :status, null: false, default: "waiting" # waiting（待っている）/ called（呼ばれた・チャット中）/ finished（終わり）/ returned（札を返した）
      t.datetime :taken_at, null: false
      t.datetime :called_at
      t.references :staff, foreign_key: true # 呼んだ行員
      t.string :staff_name # 呼んだ行員の名前（その時点の名前を残す）
      t.datetime :closed_at # 終わった・返した時刻
      t.string :closed_by # staff:<id> / customer:<id>
      t.timestamps
      t.index %i[service_date number], unique: true
      # 利用者が持てる札は同時に1枚だけ
      t.index :customer_id, unique: true, where: "status IN ('waiting', 'called')", name: "index_counter_tickets_one_active_per_customer"
      t.index :status
    end

    # チャットの発言。呼ばれた札ごと。名前はその時点の名前を残す
    create_table :counter_messages do |t|
      t.references :counter_ticket, null: false, foreign_key: true
      t.string :author_role, null: false # customer / staff
      t.integer :author_id, null: false
      t.string :author_name, null: false
      t.string :kind, null: false, default: "text" # text / withdrawal_guide（出金依頼の画面への案内）
      t.text :body, null: false
      t.datetime :created_at, null: false
    end

    # いまだれがつないでいるか（在席）。Action Cable の購読ごとに1行。subscribed で足し、unsubscribed で消す
    create_table :counter_presences do |t|
      t.string :room, null: false # "lobby"（窓口の列を見ている行員）/ "ticket:<id>"（チャット）
      t.string :role, null: false # customer / staff
      t.integer :person_id, null: false
      t.string :name, null: false
      t.datetime :created_at, null: false
      t.index %i[room role]
    end
  end
end
