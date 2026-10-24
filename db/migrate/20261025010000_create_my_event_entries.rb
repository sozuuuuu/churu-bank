# 利用者の「わたしの出来事」の索引（packs/customer の読み取りモデル）。口座ごとに、その口座の持ち主が見てよい出来事を1行ずつ。
# 出来事がコミットされたあと MyEvents::FeedJob が足す。いつでも捨てて作り直せる（bin/rails churu:my_events:rebuild）
class CreateMyEventEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :my_event_entries do |t|
      t.string :account_number, null: false
      t.string :event_id, null: false
      t.string :event_type, null: false # 種類で絞るため
      t.datetime :recorded_at, null: false, precision: 6 # 出来事の記帳時刻（並べる順）
      t.index %i[account_number event_id], unique: true
      t.index %i[account_number recorded_at id]
      t.index :event_id
    end
  end
end
