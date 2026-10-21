require "test_helper"

# 取消（逆仕訳）と、完了した振込の組戻し。元のイベントは消さずに逆向きのイベントで相殺する
class Banking::ReversalTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @bank = Banking::Bank.new(actor: "test")
    @orca = @bank.open_account(holder_name: "オルカ").account_number
    @zingiber = @bank.open_account(holder_name: "ジンジベル").account_number
  end

  def event_store = Rails.configuration.event_store
  def balance(number) = Account.find_by!(number:).balance
  def last_event_id(number) = event_store.read.stream("Account$#{number}").last.event_id
  def statement_balance(number) = Banking::Statement.new(number, date: Date.current).balance

  test "入金を取り消すと残高が戻り、通帳で取消と元の取引が対応する" do
    @bank.deposit(@orca, 100, memo: "おこづかい")
    deposit_id = last_event_id(@orca)

    @bank.reverse(@orca, deposit_id, reason: "金額まちがい", approval: approval_for_test)

    assert_equal 0, balance(@orca)
    assert_equal 0, statement_balance(@orca)
    assert_equal 0, @bank.load_account(@orca).balance
    original, reversal = Account.find_by!(number: @orca).ledger_entries.to_a
    assert_equal [ "deposit", 100 ], [ original.kind, original.amount ]
    assert_equal [ "deposit_reversal", -100, "金額まちがい" ], [ reversal.kind, reversal.amount, reversal.memo ]
    assert_equal original, reversal.original_entry
    assert_equal reversal, original.reversal_entry
    assert original.reversed?
    assert_not original.reversible?
    assert reversal.reversal?
    # 元のイベントは残っている
    assert_equal 3, event_store.read.stream("Account$#{@orca}").count
  end

  test "出金を取り消すと残高が増える" do
    @bank.deposit(@orca, 100)
    withdraw_at_counter(@orca, 30)

    @bank.reverse(@orca, last_event_id(@orca), reason: "出金していなかった", approval: approval_for_test)

    assert_equal 100, balance(@orca)
    assert_equal 100, statement_balance(@orca)
    assert_equal "withdrawal_reversal", LedgerEntry.last.kind
  end

  test "二重取消と、取消の取消はできない" do
    @bank.deposit(@orca, 100)
    deposit_id = last_event_id(@orca)
    @bank.reverse(@orca, deposit_id, reason: "まちがい", approval: approval_for_test)
    reversal_id = last_event_id(@orca)

    assert_raises(Banking::InvalidState) { @bank.reverse(@orca, deposit_id, reason: "もう一度", approval: approval_for_test) }
    assert_raises(Banking::InvalidState) { @bank.reverse(@orca, reversal_id, reason: "やっぱり", approval: approval_for_test) }
    assert_equal 0, balance(@orca)
  end

  test "使ってしまった入金は取り消せない（残高がマイナスにならない）" do
    @bank.deposit(@orca, 100)
    deposit_id = last_event_id(@orca)
    withdraw_at_counter(@orca, 60)

    assert_raises(Banking::InsufficientFunds) { @bank.reverse(@orca, deposit_id, reason: "まちがい", approval: approval_for_test) }
    assert_equal 40, balance(@orca)
  end

  test "振込や別の口座のイベントは reverse では取り消せない" do
    @bank.deposit(@orca, 100)
    deposit_id = last_event_id(@orca)
    @bank.transfer(@orca, @zingiber, 10)

    assert_raises(Banking::NotFound) { @bank.reverse(@orca, last_event_id(@orca), reason: "まちがい", approval: approval_for_test) }
    assert_raises(Banking::NotFound) { @bank.reverse(@zingiber, deposit_id, reason: "まちがい", approval: approval_for_test) }
  end

  test "凍結中でも取り消せる。理由は必須。ドライランは書き込まない" do
    @bank.deposit(@orca, 100)
    deposit_id = last_event_id(@orca)
    @bank.freeze_account(@orca, reason: "調査中")

    assert_raises(ArgumentError) { @bank.reverse(@orca, deposit_id, reason: "", approval: approval_for_test) }
    outcome = @bank.reverse(@orca, deposit_id, reason: "まちがい", dry_run: true, approval: approval_for_test)
    assert_equal [ 100, 0 ], [ outcome.balance_before, outcome.balance_after ]
    assert_equal 100, balance(@orca)

    @bank.reverse(@orca, deposit_id, reason: "まちがい", approval: approval_for_test)
    assert_equal 0, balance(@orca)
  end

  test "完了した振込を組戻しすると、振込先から引き戻して振込元へ払い戻す" do
    @bank.deposit(@orca, 100)
    transfer_id = @bank.transfer(@orca, @zingiber, 30).transfer_id
    perform_enqueued_jobs(only: Transfers::SettleJob)
    assert Transfer.find_by!(transfer_id:).reversible?

    outcome = @bank.reverse_transfer(transfer_id, reason: "振込先まちがい", approval: approval_for_test)

    assert_equal [ 70, 100 ], [ outcome.balance_before, outcome.balance_after ]
    assert_equal [ 100, 0 ], [ balance(@orca), balance(@zingiber) ]
    assert_equal [ 100, 0 ], [ statement_balance(@orca), statement_balance(@zingiber) ]
    transfer = Transfer.find_by!(transfer_id:)
    assert_equal [ "reversed", "振込先まちがい" ], [ transfer.status, transfer.reversal_reason ]
    assert_equal %w[transfer_in transfer_reversal], LedgerEntry.where(account_number: @zingiber).pluck(:kind)
    assert_equal "transfer_refund", LedgerEntry.where(account_number: @orca).last.kind

    types = event_store.read.stream("Transfer$#{transfer_id}").map { it.class.name.demodulize }
    assert_equal %w[TransferDebited TransferRequested TransferCredited TransferCompleted
                    TransferCreditReversed TransferRefunded TransferReversed].sort, types.sort
  end

  test "組戻しは完了した振込に1回だけ。振込先の残高が足りなければ何も書かない" do
    @bank.deposit(@orca, 100)
    transfer_id = @bank.transfer(@orca, @zingiber, 30).transfer_id
    assert_raises(Banking::InvalidState) { @bank.reverse_transfer(transfer_id, reason: "処理中", approval: approval_for_test) }
    perform_enqueued_jobs(only: Transfers::SettleJob)

    withdraw_at_counter(@zingiber, 10)
    assert_raises(Banking::InsufficientFunds) { @bank.reverse_transfer(transfer_id, reason: "まちがい", approval: approval_for_test) }
    assert_equal "completed", Transfer.find_by!(transfer_id:).status
    assert_equal [ 70, 20 ], [ balance(@orca), balance(@zingiber) ]

    @bank.deposit(@zingiber, 10)
    @bank.reverse_transfer(transfer_id, reason: "まちがい", approval: approval_for_test)
    assert_raises(Banking::InvalidState) { @bank.reverse_transfer(transfer_id, reason: "もう一度", approval: approval_for_test) }
    assert_equal [ 100, 0 ], [ balance(@orca), balance(@zingiber) ]
  end

  test "組戻しになった振込（失敗）と、ない振込は組戻しできない" do
    @bank.deposit(@orca, 100)
    @bank.freeze_account(@zingiber, reason: "調査中")
    transfer_id = @bank.transfer(@orca, @zingiber, 30).transfer_id
    perform_enqueued_jobs(only: Transfers::SettleJob)

    assert_raises(Banking::InvalidState) { @bank.reverse_transfer(transfer_id, reason: "まちがい", approval: approval_for_test) }
    assert_raises(Banking::NotFound) { @bank.reverse_transfer(SecureRandom.uuid, reason: "まちがい", approval: approval_for_test) }
  end
end
