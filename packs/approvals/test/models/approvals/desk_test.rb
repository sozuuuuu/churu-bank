require "test_helper"

# 二人承認（TODO の Q2）: 取消・組戻し・凍結の解除は「申請 → 別の行員が承認 → 実行」
class Approvals::DeskTest < ActiveSupport::TestCase
  setup do
    @tama = Approvals::Desk.new(actor: "staff:1")
    @kuro = Approvals::Desk.new(actor: "staff:2")
    @bank = Banking::Bank.new(actor: "staff:1")
    @orca = @bank.open_account(holder_name: "オルカ").account_number
    @bank.deposit(@orca, 100, memo: "おこづかい")
    @deposit_id = LedgerEntry.last.event_id
  end

  def event_store = Rails.configuration.event_store

  test "申請しただけでは実行しない。承認待ちに並ぶ（だれが・何を・理由）" do
    submitted = @tama.request_reversal(@orca, @deposit_id, reason: "金額まちがい")

    assert_equal [ 100, 0 ], [ submitted.outcome.balance_before, submitted.outcome.balance_after ]
    assert_equal 100, Account.find_by!(number: @orca).balance
    request = ApprovalRequest.find_by!(approval_id: submitted.approval_id)
    assert_equal [ "pending", "reversal", "staff:1", "金額まちがい", @orca ],
                 [ request.status, request.kind, request.requested_by, request.reason, request.account_number ]
    assert_match "オルカ（#{@orca}）の入金 100 ちゅ〜る", request.summary
  end

  test "申請した本人は承認できない（試算もできない）" do
    approval_id = @tama.request_reversal(@orca, @deposit_id, reason: "金額まちがい").approval_id

    error = assert_raises(Banking::InvalidState) { @tama.approve(approval_id) }
    assert_match "申請した本人", error.message
    assert_raises(Banking::InvalidState) { @tama.approve(approval_id, dry_run: true) }
    assert ApprovalRequest.find_by!(approval_id:).pending?
    assert_equal 100, Account.find_by!(number: @orca).balance
  end

  test "別の行員が承認すると実行される。申請・承認・実行のイベントと actor が残り、銀行のイベントもリンクされる" do
    approval_id = @tama.request_reversal(@orca, @deposit_id, reason: "金額まちがい").approval_id

    outcome = @kuro.approve(approval_id)

    assert_equal 0, outcome.balance_after
    assert_equal 0, Account.find_by!(number: @orca).balance
    request = ApprovalRequest.find_by!(approval_id:)
    assert_equal [ "executed", "staff:2" ], [ request.status, request.decided_by ]

    stream = event_store.read.stream("Approval$#{approval_id}").to_a
    assert_equal %w[ApprovalRequested ApprovalGranted ApprovalExecuted DepositReversed],
                 stream.map { it.class.name.demodulize }
    assert_equal %w[staff:1 staff:2 staff:2 staff:2], stream.map { it.metadata[:actor] }
    reversed = stream.last
    assert_equal [ approval_id, "staff:1", "staff:2" ], reversed.metadata.to_h.values_at(:approval_id, :requested_by, :approved_by)
    assert_equal [ reversed.event_id ], stream[2].data[:event_ids]
  end

  test "承認の試算（dry_run）は何も書かない" do
    approval_id = @tama.request_reversal(@orca, @deposit_id, reason: "金額まちがい").approval_id

    assert @kuro.approve(approval_id, dry_run: true).dry_run?
    assert ApprovalRequest.find_by!(approval_id:).pending?
    assert_equal 100, Account.find_by!(number: @orca).balance
  end

  test "二重に承認しても1回しか実行しない" do
    approval_id = @tama.request_reversal(@orca, @deposit_id, reason: "金額まちがい").approval_id
    @kuro.approve(approval_id)

    assert_raises(Banking::InvalidState) { @kuro.approve(approval_id) }
    assert_raises(Banking::InvalidState) { Approvals::Desk.new(actor: "staff:3").approve(approval_id) }
    assert_equal 1, event_store.read.of_type(Banking::Events::DepositReversed).count
  end

  test "却下（理由は必須）。銀行は何も変わらず、あとから承認できない。申請者は自分の申請を却下できない" do
    approval_id = @tama.request_reversal(@orca, @deposit_id, reason: "金額まちがい").approval_id

    assert_raises(Banking::InvalidState) { @tama.reject(approval_id, reason: "やめた") }
    assert_raises(ArgumentError) { @kuro.reject(approval_id, reason: " ") }
    @kuro.reject(approval_id, reason: "証跡がない")

    request = ApprovalRequest.find_by!(approval_id:)
    assert_equal [ "rejected", "staff:2", "証跡がない" ], [ request.status, request.decided_by, request.reject_reason ]
    assert_raises(Banking::InvalidState) { @kuro.approve(approval_id) }
    assert_equal 100, Account.find_by!(number: @orca).balance
  end

  test "取り下げは申請した本人だけ" do
    approval_id = @tama.request_reversal(@orca, @deposit_id, reason: "金額まちがい").approval_id

    assert_raises(Banking::InvalidState) { @kuro.withdraw(approval_id) }
    @tama.withdraw(approval_id)
    assert_equal [ "withdrawn", "staff:1" ], ApprovalRequest.find_by!(approval_id:).then { [ it.status, it.decided_by ] }
  end

  test "同じ対象の承認待ちは1つだけ。却下されたらまた申請できる" do
    approval_id = @tama.request_reversal(@orca, @deposit_id, reason: "金額まちがい").approval_id

    assert_raises(Banking::InvalidState) { @kuro.request_reversal(@orca, @deposit_id, reason: "やっぱり") }
    @kuro.reject(approval_id, reason: "だめ")
    assert @kuro.request_reversal(@orca, @deposit_id, reason: "やっぱり").approval_id
  end

  test "いまできない操作は申請できない（理由がない・取り消せない取引）" do
    assert_raises(ArgumentError) { @tama.request_reversal(@orca, @deposit_id, reason: "") }
    assert_raises(Banking::NotFound) { @tama.request_reversal(@orca, SecureRandom.uuid, reason: "まちがい") }
    assert_raises(Banking::InvalidState) { @tama.request_unfreeze(@orca, reason: "凍結していない") }
    assert_empty ApprovalRequest.all
  end

  test "承認のときに銀行で失敗したら全部戻り、承認待ちのまま" do
    approval_id = @tama.request_reversal(@orca, @deposit_id, reason: "金額まちがい").approval_id
    withdraw_at_counter(@orca, 50) # 申請のあとで使ってしまった

    assert_raises(Banking::InsufficientFunds) { @kuro.approve(approval_id) }
    assert ApprovalRequest.find_by!(approval_id:).pending?
    assert_equal 1, event_store.read.stream("Approval$#{approval_id}").count
  end

  test "凍結は一人ですぐ。解除は申請 → 承認" do
    @bank.freeze_account(@orca, reason: "不正の疑い")
    assert_raises(Banking::InvalidState) { @bank.unfreeze_account(@orca) }

    approval_id = @tama.request_unfreeze(@orca, reason: "本人確認できた").approval_id
    assert_equal "frozen", Account.find_by!(number: @orca).status
    @kuro.approve(approval_id)

    assert_equal "active", Account.find_by!(number: @orca).status
  end

  test "振込の組戻しも申請 → 承認" do
    zingiber = @bank.open_account(holder_name: "ジンジベル").account_number
    transfer_id = Banking::Bank.new(actor: "customer:1").transfer(@orca, zingiber, 30).transfer_id
    @bank.settle_transfer(transfer_id)

    approval_id = @tama.request_transfer_reversal(transfer_id, reason: "振込先まちがい").approval_id
    assert_equal "completed", Transfer.find_by!(transfer_id:).status
    @kuro.approve(approval_id)

    assert_equal "reversed", Transfer.find_by!(transfer_id:).status
    assert_equal [ 100, 0 ], [ @orca, zingiber ].map { Account.find_by!(number: it).balance }
  end

  test "読み取りモデルを作り直しても同じになる" do
    executed = @tama.request_reversal(@orca, @deposit_id, reason: "金額まちがい").approval_id
    @kuro.approve(executed)
    @bank.freeze_account(@orca, reason: "不正の疑い")
    rejected = @tama.request_unfreeze(@orca, reason: "本人確認できた").approval_id
    @kuro.reject(rejected, reason: "まだ")
    columns = %i[approval_id status decided_by reject_reason]
    before = ApprovalRequest.order(:approval_id).pluck(*columns)

    Approvals::Projection.rebuild

    assert_equal before, ApprovalRequest.order(:approval_id).pluck(*columns)
  end
end
