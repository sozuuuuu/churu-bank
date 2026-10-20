require "test_helper"

# 振込: 受付と引き落とし（同期）→ Transfers::SettleJob（非同期）→ 入金で完了 / 組戻しで失敗
class Banking::TransferTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @bank = Banking::Bank.new(actor: "test")
    @orca = @bank.open_account(holder_name: "オルカ").account_number
    @zingiber = @bank.open_account(holder_name: "ジンジベル").account_number
    @bank.deposit(@orca, 100)
  end

  def event_store = Rails.configuration.event_store
  def balance(number) = Account.find_by!(number:).balance

  test "受付の時点で引き落とされ、ジョブで入金されて完了する" do
    outcome = @bank.transfer(@orca, @zingiber, 30, memo: "おやつ代")

    transfer = Transfer.find_by!(transfer_id: outcome.transfer_id)
    assert_equal "requested", transfer.status
    assert_equal 70, balance(@orca)
    assert_equal 0, balance(@zingiber)
    assert_enqueued_jobs 1, only: Transfers::SettleJob

    perform_enqueued_jobs(only: Transfers::SettleJob)

    assert_equal "completed", transfer.reload.status
    assert_equal 30, balance(@zingiber)
    entry = LedgerEntry.find_by!(account_number: @zingiber)
    assert_equal [ "transfer_in", @orca, "おやつ代" ], [ entry.kind, entry.counterparty, entry.memo ]
  end

  test "振込のストリームから、口座側のお金の動きまで辿れる" do
    outcome = @bank.transfer(@orca, @zingiber, 30)
    perform_enqueued_jobs(only: Transfers::SettleJob)

    types = event_store.read.stream("Transfer$#{outcome.transfer_id}").map { it.class.name.demodulize }
    assert_equal %w[TransferDebited TransferRequested TransferCredited TransferCompleted].sort, types.sort
  end

  test "入金はきっかけの引き落としと同じ correlation_id を持つ" do
    outcome = @bank.transfer(@orca, @zingiber, 30)
    perform_enqueued_jobs(only: Transfers::SettleJob)

    debited, credited = [ @orca, @zingiber ].map do |number|
      event_store.read.stream("Account$#{number}").of_type(
        [ Banking::Events::TransferDebited, Banking::Events::TransferCredited ]
      ).last
    end
    assert_equal debited.correlation_id, credited.correlation_id
    assert_equal debited.event_id, credited.causation_id
    assert_equal "transfer-settlement", credited.metadata[:actor]
    assert outcome.transfer_id
  end

  test "残高不足ならその場で失敗し、何も残らない" do
    assert_raises(Banking::InsufficientFunds) { @bank.transfer(@orca, @zingiber, 101) }

    assert_equal 0, Transfer.count
    assert_no_enqueued_jobs only: Transfers::SettleJob
  end

  test "存在しない口座・自分の口座には振り込めない" do
    assert_raises(Banking::NotFound) { @bank.transfer(@orca, "9999999", 1) }
    assert_raises(ArgumentError) { @bank.transfer(@orca, @orca, 1) }
  end

  test "振込先が凍結中なら組戻しになって、お金が戻る" do
    @bank.freeze_account(@zingiber, reason: "テスト")

    outcome = @bank.transfer(@orca, @zingiber, 30)
    assert_match "組戻し", outcome.warnings.first
    assert_equal 70, balance(@orca)

    perform_enqueued_jobs(only: Transfers::SettleJob)

    transfer = Transfer.find_by!(transfer_id: outcome.transfer_id)
    assert_equal "failed", transfer.status
    assert_match "凍結", transfer.failure_reason
    assert_equal 100, balance(@orca)
    assert_equal 0, balance(@zingiber)
    assert_equal %w[deposit transfer_out transfer_refund],
                 LedgerEntry.where(account_number: @orca).order(:id).pluck(:kind)
  end

  test "ジョブが2回動いても二重に入金されない" do
    outcome = @bank.transfer(@orca, @zingiber, 30)

    2.times { @bank.settle_transfer(outcome.transfer_id) }

    assert_equal 30, balance(@zingiber)
    assert_equal 1, LedgerEntry.where(account_number: @zingiber).count
  end

  test "ドライランは何も書き込まない" do
    outcome = @bank.transfer(@orca, @zingiber, 30, dry_run: true)

    assert_equal [ 100, 70 ], [ outcome.balance_before, outcome.balance_after ]
    assert_equal %w[TransferDebited TransferRequested], outcome.events.map { it.class.name.demodulize }
    assert_equal 0, Transfer.count
    assert_equal 100, balance(@orca)
  end

  test "時点指定の残高にも振込が入る" do
    @bank.transfer(@orca, @zingiber, 30)
    perform_enqueued_jobs(only: Transfers::SettleJob)

    assert_equal 70, Banking::Statement.new(@orca, date: Date.current).balance
    assert_equal 30, Banking::Statement.new(@zingiber, date: Date.current).balance
  end
end
