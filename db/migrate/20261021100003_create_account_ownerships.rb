# 利用者と口座のひも付け（identity パック）。口座番号は銀行パックの Account#number だが、
# 銀行パックは User を知らないので外部キーは張らない
class CreateAccountOwnerships < ActiveRecord::Migration[8.1]
  def change
    create_table :account_ownerships do |t|
      t.references :user, null: false, foreign_key: true
      t.string :account_number, null: false

      t.timestamps
    end
    add_index :account_ownerships, %i[user_id account_number], unique: true
    add_index :account_ownerships, :account_number
  end
end
