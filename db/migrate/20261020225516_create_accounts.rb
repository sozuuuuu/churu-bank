# 読み取りモデル: 口座一覧。正はイベントストア（Account$<番号> ストリーム）。
class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :number, null: false
      t.string :holder_name, null: false
      t.string :status, null: false
      t.integer :balance, null: false, default: 0
      t.date :opened_on, null: false

      t.timestamps
    end
    add_index :accounts, :number, unique: true
  end
end
