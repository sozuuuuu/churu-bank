# 銀行からのお知らせ（packs/notices）。イベントソーシングにはしない（README の「お知らせ」の節）
class CreateNotices < ActiveRecord::Migration[8.1]
  def change
    create_table :notices do |t|
      t.string :kind, null: false # info / request / maintenance（あとで campaign）
      t.string :title, null: false
      t.text :body, null: false, default: ""
      t.boolean :important, null: false, default: false # 閉じるまで出し続ける
      t.datetime :starts_at, null: false
      t.datetime :ends_at # なし = 終わりなし
      t.string :audience, null: false, default: "everyone" # everyone / selected（notice_targets の利用者だけ）
      t.string :posted_by # だれが出したか（admin:<メール> / seed など）
      t.timestamps
      t.index %i[starts_at ends_at]
    end

    create_table :notice_targets do |t|
      t.references :notice, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
      t.index %i[notice_id user_id], unique: true
    end

    # 利用者ごとの既読（開いた）と、閉じた（吹き出しから消した）
    create_table :notice_receipts do |t|
      t.references :notice, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :read_at
      t.datetime :dismissed_at
      t.timestamps
      t.index %i[notice_id user_id], unique: true
    end
  end
end
