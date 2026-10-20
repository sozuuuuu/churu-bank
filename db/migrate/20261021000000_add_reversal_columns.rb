# 取消（逆仕訳）と振込の組戻しを読み取りモデルに載せる
class AddReversalColumns < ActiveRecord::Migration[8.1]
  def change
    # 取消の行 → 元の行（reversal_of）、元の行 → 取消の行（reversed_by）。どちらもイベント ID
    add_column :ledger_entries, :reversal_of, :string
    add_column :ledger_entries, :reversed_by, :string
    add_index :ledger_entries, :reversal_of

    add_column :transfers, :reversed_at, :datetime
    add_column :transfers, :reversal_reason, :string
  end
end
