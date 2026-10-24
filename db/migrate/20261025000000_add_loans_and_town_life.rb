# ちゅ〜るローン（packs/banking の貸付）の読み取りモデルと、ねこ町の暮らし（packs/simulation）の借金・手紙・遊び場のための表
class AddLoansAndTownLife < ActiveRecord::Migration[8.1]
  def change
    # 貸付の読み取りモデル（Projections::LoanProjection が書く）。正はイベントストアの Loan$<貸付ID>
    create_table :loans do |t|
      t.string :loan_id, null: false
      t.string :account_number, null: false
      t.integer :principal, null: false   # 借りた額（口座に入った額）
      t.integer :fee, null: false         # 手数料（利息）。借りたときに決まり、返す額に足す
      t.integer :outstanding, null: false # まだ返していない額
      t.string :status, null: false       # open / settled
      t.string :memo
      t.datetime :granted_at, null: false
      t.datetime :settled_at
      t.timestamps
      t.index :loan_id, unique: true
      t.index %i[account_number status]
    end

    # 住民どうしの借用書（お金の動きは銀行の振込。こちらは「だれがだれにいくら借りているか」の町の記録）
    create_table :simulation_debts do |t|
      t.string :lender, null: false
      t.string :borrower, null: false
      t.integer :amount, null: false      # 借りた額
      t.integer :repaid, null: false, default: 0
      t.integer :day                      # 借りた日（町の何日目か）
      t.timestamps
      t.index %i[borrower lender]
    end

    # 手紙の記録（画面の「手紙の流れ」。新しいものだけ残す）
    create_table :simulation_letters do |t|
      t.string :sender, null: false
      t.string :recipient, null: false
      t.string :kind, null: false         # ask / reply / refuse / trouble / lent / restart
      t.string :text, null: false
      t.integer :day
      t.timestamps
    end

    add_column :simulation_residents, :letters_received, :integer, null: false, default: 0
    add_column :simulation_residents, :letters_sent, :integer, null: false, default: 0
    add_column :simulation_residents, :rent_paid_day, :integer # 最後に家賃を払った日
    add_column :simulation_controls, :landlord_account, :string # 家賃を受け取る口座（ねこ町の大家さん）
    add_column :simulation_controls, :places, :json             # 遊び場の名前 => 口座番号
  end
end
