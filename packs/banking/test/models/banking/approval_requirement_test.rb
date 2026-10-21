require "test_helper"

# 二人承認（TODO の Q2）: 取消・組戻し・凍結の解除は、申請者とは別の行員の承認（Bank::Approval）があるときだけ。
# 申請・承認の流れそのものは packs/approvals。銀行は「承認がある」「申請者と実行者が別」だけを確かめる
class Banking::ApprovalRequirementTest < ActiveSupport::TestCase
  setup do
    @bank = Banking::Bank.new(actor: "staff:2")
    @orca = @bank.open_account(holder_name: "オルカ").account_number
    @bank.deposit(@orca, 100)
    @deposit_id = LedgerEntry.last.event_id
  end

  def event_store = Rails.configuration.event_store

  test "承認なしでは取消・組戻し・凍結の解除はできない。ドライラン（試算）はできる" do
    assert_raises(Banking::InvalidState) { @bank.reverse(@orca, @deposit_id, reason: "まちがい") }
    assert @bank.reverse(@orca, @deposit_id, reason: "まちがい", dry_run: true).dry_run?

    @bank.freeze_account(@orca, reason: "不正の疑い") # 凍結は一人ですぐ
    assert_raises(Banking::InvalidState) { @bank.unfreeze_account(@orca) }
    assert_raises(Banking::InvalidState) { @bank.reverse_transfer(SecureRandom.uuid, reason: "まちがい") }
    assert_equal "frozen", Account.find_by!(number: @orca).status
  end

  test "申請した本人が実行者なら InvalidState" do
    approval = Banking::Bank::Approval.new(id: "a1", requested_by: "staff:2")

    error = assert_raises(Banking::InvalidState) { @bank.reverse(@orca, @deposit_id, reason: "まちがい", approval:) }
    assert_match "申請した本人", error.message
  end

  test "別の行員の承認なら実行し、metadata に approval_id・requested_by・approved_by が残る" do
    approval = Banking::Bank::Approval.new(id: "a1", requested_by: "staff:1")

    @bank.reverse(@orca, @deposit_id, reason: "まちがい", approval:)

    event = event_store.read.of_type(Banking::Events::DepositReversed).last
    assert_equal({ actor: "staff:2", approval_id: "a1", requested_by: "staff:1", approved_by: "staff:2" },
                 event.metadata.to_h.slice(:actor, :approval_id, :requested_by, :approved_by))
  end
end
