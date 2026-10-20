class AddTransferColumnsToLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :ledger_entries, :counterparty, :string # 振込の相手口座
    add_column :ledger_entries, :transfer_id, :string
    add_index :ledger_entries, :transfer_id
  end
end
