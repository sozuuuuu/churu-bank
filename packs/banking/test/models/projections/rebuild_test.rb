require "test_helper"

# 読み取りモデルを捨ててイベントストアから作り直すと、元とまったく同じになる
class Projections::RebuildTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  IGNORED = %w[id created_at updated_at].freeze

  def snapshot
    {
      accounts: Account.order(:number).map { it.attributes.except(*IGNORED) },
      ledger_entries: LedgerEntry.order(:event_id).map { it.attributes.except(*IGNORED) },
      transfers: Transfer.order(:transfer_id).map { it.attributes.except(*IGNORED) }
    }
  end

  test "作り直す前と後で読み取りモデルが一致し、非同期ハンドラは動かない" do
    bank = Banking::Bank.new(actor: "test")
    orca = bank.open_account(holder_name: "オルカ").account_number
    zingiber = bank.open_account(holder_name: "ジンジベル").account_number
    frozen = bank.open_account(holder_name: "こおり").account_number

    bank.deposit(orca, 1000, memo: "おこづかい", value_date: Date.current - 3)
    bank.withdraw(orca, 100)
    bank.deposit(orca, 5)
    bank.reverse(orca, LedgerEntry.last.event_id, reason: "まちがい")
    completed = bank.transfer(orca, zingiber, 300).transfer_id
    bank.freeze_account(frozen, reason: "調査中")
    bank.transfer(orca, frozen, 50) # 振込先が凍結中 → 組戻し
    perform_enqueued_jobs(only: Transfers::SettleJob)
    bank.reverse_transfer(completed, reason: "振込先まちがい")
    bank.transfer(orca, zingiber, 10) # 処理中のまま
    bank.pay_interest(date: Date.current - 1, annual_rate: "0.365")
    clear_enqueued_jobs

    before = snapshot
    assert_not_empty before[:ledger_entries]

    count = nil
    assert_no_enqueued_jobs { count = Projections::Rebuild.new.call }

    assert_equal Rails.configuration.event_store.read.count, count
    assert_equal before, snapshot
  end

  test "読み取りモデルが壊れていても作り直せる" do
    bank = Banking::Bank.new(actor: "test")
    number = bank.open_account(holder_name: "オルカ").account_number
    bank.deposit(number, 100)
    Account.find_by!(number:).update!(balance: 999_999)
    LedgerEntry.delete_all

    Projections::Rebuild.new.call

    assert_equal 100, Account.find_by!(number:).balance
    assert_equal [ 100 ], LedgerEntry.pluck(:amount)
  end
end
