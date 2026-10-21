require "test_helper"

# 窓口取引（TODO の Q1）: 出金は利用者の出金依頼があるときだけ。行員が処理（出金）するか断る。処理の前なら利用者が取り消せる
class Banking::WithdrawalRequestTest < ActiveSupport::TestCase
  setup do
    @customer_bank = Banking::Bank.new(actor: "customer:1")
    @staff_bank = Banking::Bank.new(actor: "staff:1")
    @orca = @staff_bank.open_account(holder_name: "オルカ").account_number
    @staff_bank.deposit(@orca, 100)
  end

  def event_store = Rails.configuration.event_store

  test "依頼なしに出金する入口はない（Bank#withdraw はない）" do
    assert_not_respond_to @staff_bank, :withdraw
  end

  test "依頼を出してもお金は動かない。行員の一覧（読み取りモデル）に受付中で並ぶ" do
    outcome = @customer_bank.request_withdrawal(@orca, 30, memo: "おやつ代")

    assert_equal [ 100, 70 ], [ outcome.balance_before, outcome.balance_after ]
    assert_equal 100, Account.find_by!(number: @orca).balance
    request = WithdrawalRequest.find_by!(request_id: outcome.request_id)
    assert_equal [ "requested", 30, "おやつ代", "customer:1" ],
                 [ request.status, request.amount, request.memo, request.requested_by ]
    assert_equal [ request ], WithdrawalRequest.open.to_a
  end

  test "行員が処理すると出金され、依頼は出金済み。MoneyWithdrawn に request_id、依頼のストリームにもリンク" do
    request_id = @customer_bank.request_withdrawal(@orca, 30).request_id

    outcome = @staff_bank.process_withdrawal(request_id)

    assert_equal [ 100, 70 ], [ outcome.balance_before, outcome.balance_after ]
    assert_equal 70, Account.find_by!(number: @orca).balance
    request = WithdrawalRequest.find_by!(request_id:)
    assert_equal [ "processed", "staff:1" ], [ request.status, request.closed_by ]
    withdrawn = event_store.read.of_type(Banking::Events::MoneyWithdrawn).last
    assert_equal request_id, withdrawn.data[:request_id]
    assert_equal withdrawn.event_id, request.withdrawal_event_id
    assert_equal %w[WithdrawalRequested WithdrawalRequestProcessed MoneyWithdrawn],
                 event_store.read.stream("WithdrawalRequest$#{request_id}").map { it.class.name.demodulize }
    assert_equal "withdrawal", LedgerEntry.last.kind
  end

  test "二重に処理しても1回しか出金しない" do
    request_id = @customer_bank.request_withdrawal(@orca, 30).request_id
    @staff_bank.process_withdrawal(request_id)

    error = assert_raises(Banking::InvalidState) { @staff_bank.process_withdrawal(request_id) }
    assert_match "出金済み", error.message
    assert_equal 70, Account.find_by!(number: @orca).balance
  end

  test "処理と取消が同時なら後から来た方が負ける（expected_version）" do
    request_id = @customer_bank.request_withdrawal(@orca, 30).request_id
    stale = AggregateRoot::Repository.new(event_store)
                                     .load(Banking::WithdrawalRequest.new(request_id), "WithdrawalRequest$#{request_id}")
    @staff_bank.process_withdrawal(request_id)

    stale.cancel!
    assert_raises(RubyEventStore::WrongExpectedEventVersion) do
      AggregateRoot::Repository.new(event_store).store(stale, "WithdrawalRequest$#{request_id}")
    end
  end

  test "ドライランは何も書かない" do
    request_id = @customer_bank.request_withdrawal(@orca, 30, dry_run: true).request_id
    assert_nil WithdrawalRequest.find_by(request_id:)

    request_id = @customer_bank.request_withdrawal(@orca, 30).request_id
    assert @staff_bank.process_withdrawal(request_id, dry_run: true).dry_run?
    assert_equal 100, Account.find_by!(number: @orca).balance
    assert WithdrawalRequest.find_by!(request_id:).open?
  end

  test "行員が断る（理由は必須）。お金は動かず、あとから処理も取消もできない" do
    request_id = @customer_bank.request_withdrawal(@orca, 30).request_id

    assert_raises(ArgumentError) { @staff_bank.reject_withdrawal(request_id, reason: " ") }
    @staff_bank.reject_withdrawal(request_id, reason: "本人確認ができません")

    request = WithdrawalRequest.find_by!(request_id:)
    assert_equal [ "rejected", "本人確認ができません", "staff:1" ], [ request.status, request.reject_reason, request.closed_by ]
    assert_equal 100, Account.find_by!(number: @orca).balance
    assert_raises(Banking::InvalidState) { @staff_bank.process_withdrawal(request_id) }
    assert_raises(Banking::InvalidState) { @customer_bank.cancel_withdrawal(request_id, from: @orca) }
  end

  test "利用者は処理の前なら取り消せる。処理したあとは取り消せない" do
    request_id = @customer_bank.request_withdrawal(@orca, 30).request_id
    @customer_bank.cancel_withdrawal(request_id, from: @orca)
    assert_equal "cancelled", WithdrawalRequest.find_by!(request_id:).status
    assert_raises(Banking::InvalidState) { @staff_bank.process_withdrawal(request_id) }

    processed = @customer_bank.request_withdrawal(@orca, 30).request_id
    @staff_bank.process_withdrawal(processed)
    assert_raises(Banking::InvalidState) { @customer_bank.cancel_withdrawal(processed, from: @orca) }
  end

  test "他人の口座の依頼は取り消せない（NotFound）" do
    zingiber = @staff_bank.open_account(holder_name: "ジンジベル").account_number
    request_id = @customer_bank.request_withdrawal(@orca, 30).request_id

    assert_raises(Banking::NotFound) { @customer_bank.cancel_withdrawal(request_id, from: zingiber) }
    assert_raises(Banking::NotFound) { @staff_bank.process_withdrawal(SecureRandom.uuid) }
  end

  test "依頼のときに残高・凍結を確かめる。処理のときに足りなくなっていたら出金しない" do
    assert_raises(Banking::InsufficientFunds) { @customer_bank.request_withdrawal(@orca, 101) }
    assert_raises(ArgumentError) { @customer_bank.request_withdrawal(@orca, 0) }

    first = @customer_bank.request_withdrawal(@orca, 80).request_id
    second = @customer_bank.request_withdrawal(@orca, 80).request_id # 依頼ではお金を押さえない
    @staff_bank.process_withdrawal(first)

    assert_raises(Banking::InsufficientFunds) { @staff_bank.process_withdrawal(second) }
    assert WithdrawalRequest.find_by!(request_id: second).open?
    assert_equal 20, Account.find_by!(number: @orca).balance

    @staff_bank.freeze_account(@orca, reason: "不正の疑い")
    assert_raises(Banking::InvalidState) { @customer_bank.request_withdrawal(@orca, 1) }
  end

  test "読み取りモデルを作り直しても同じになる" do
    request_id = @customer_bank.request_withdrawal(@orca, 30).request_id
    @staff_bank.process_withdrawal(request_id)
    rejected = @customer_bank.request_withdrawal(@orca, 10).request_id
    @staff_bank.reject_withdrawal(rejected, reason: "だめ")
    columns = %i[request_id status reject_reason withdrawal_event_id]
    before = WithdrawalRequest.order(:request_id).pluck(*columns)

    Projections::Rebuild.new.call

    assert_equal before, WithdrawalRequest.order(:request_id).pluck(*columns)
    assert_equal 70, Account.find_by!(number: @orca).balance
  end
end
