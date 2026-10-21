require "test_helper"

# 二人承認（TODO の Q2）: 取消・組戻し・凍結の解除は「申請 → 別の行員が承認 → 実行」。行員を切り替えて確かめる
class Admin::ApprovalsTest < ActionDispatch::IntegrationTest
  setup do
    @tama = create_staff(name: "たま")
    @kuro = create_staff(name: "くろ")
    @bank = Banking::Bank.new(actor: "test")
    @orca = @bank.open_account(holder_name: "オルカ").account_number
    @bank.deposit(@orca, 100, memo: "おこづかい")
    @entry = LedgerEntry.find_by!(account_number: @orca, kind: "deposit")
  end

  def balance = Account.find_by!(number: @orca).balance

  def request_reversal_as_tama
    sign_in_as_staff @tama
    post admin_account_reversals_path(@orca), params: { event_id: @entry.event_id, reason: "金額まちがい" }
    ApprovalRequest.pending.sole
  end

  test "たまが申請 → 承認待ちに並ぶ。たま本人には承認・却下を出さず、取り下げだけ" do
    request = request_reversal_as_tama

    get admin_approvals_path
    assert_select "nav a[href=?] .badge", admin_approvals_path, "1"
    assert_select "tr##{dom_id(request)}", /入出金の取消.*オルカ.*金額まちがい.*たま/m
    assert_select "tr##{dom_id(request)} a", text: "承認する", count: 0
    assert_select "tr##{dom_id(request)} button", "取り下げる"
  end

  test "申請した本人は承認できない（画面からも、URL を直接たたいても）" do
    request = request_reversal_as_tama

    get new_admin_approval_grant_path(request)
    assert_match "申請した本人は承認できません", response.body
    assert_select "input[type=submit][value=?]", "承認して実行する", count: 0
    post admin_approval_grant_path(request)
    assert_response :unprocessable_entity
    assert_equal 100, balance
    assert request.reload.pending?
  end

  test "くろが承認すると実行される。だれが申請・承認したかが残る。二重には実行しない" do
    request = request_reversal_as_tama
    sign_in_as_staff @kuro

    get admin_approvals_path
    assert_select "tr##{dom_id(request)} a", text: "承認する"
    get new_admin_approval_grant_path(request)
    assert_select "turbo-frame#approval", /100 ちゅ〜る → .*0 ちゅ〜る/m
    assert_equal 100, balance

    post admin_approval_grant_path(request)
    assert_redirected_to admin_approvals_path
    assert_equal 0, balance
    assert_equal [ "executed", @tama.actor, @kuro.actor ], request.reload.then { [ it.status, it.requested_by, it.decided_by ] }
    reversed = Rails.configuration.event_store.read.of_type(Banking::Events::DepositReversed).last
    assert_equal [ @kuro.actor, @tama.actor ], reversed.metadata.to_h.values_at(:actor, :requested_by)

    post admin_approval_grant_path(request)
    assert_response :unprocessable_entity
    assert_equal 1, Rails.configuration.event_store.read.of_type(Banking::Events::DepositReversed).count

    get admin_approvals_path
    assert_select "tr##{dom_id(request)}", /実行済み.*くろ/m
  end

  test "くろが却下（理由つき）。何も実行されない" do
    request = request_reversal_as_tama
    sign_in_as_staff @kuro

    post admin_approval_rejection_path(request), params: { reason: "", preview: "1" }
    assert_response :unprocessable_entity
    post admin_approval_rejection_path(request), params: { reason: "証跡がない", preview: "1" }
    assert_match "まだ却下していません", response.body
    post admin_approval_rejection_path(request), params: { reason: "証跡がない" }
    assert_redirected_to admin_approvals_path

    assert_equal [ "rejected", "証跡がない", @kuro.actor ], request.reload.then { [ it.status, it.reject_reason, it.decided_by ] }
    assert_equal 100, balance
    post admin_approval_grant_path(request)
    assert_response :unprocessable_entity
  end

  test "たまは取り下げられる。くろは取り下げられない" do
    request = request_reversal_as_tama
    sign_in_as_staff @kuro
    post admin_approval_withdrawal_path(request)
    assert_match "申請した本人だけ", flash[:alert]

    sign_in_as_staff @tama
    post admin_approval_withdrawal_path(request)
    assert_equal "withdrawn", request.reload.status
  end

  test "凍結は一人ですぐ。解除は申請 → 別の行員の承認" do
    sign_in_as_staff @tama
    post admin_account_freeze_path(@orca)
    assert_equal "frozen", Account.find_by!(number: @orca).status

    delete admin_account_freeze_path(@orca), params: { reason: "" }
    assert_match "申請の理由を入れてください", flash[:alert]
    delete admin_account_freeze_path(@orca), params: { reason: "本人確認できた" }
    assert_equal "frozen", Account.find_by!(number: @orca).status
    get admin_account_path(@orca)
    assert_match "凍結の解除を申請中", response.body

    sign_in_as_staff @kuro
    post admin_approval_grant_path(ApprovalRequest.pending.sole)
    assert_equal "active", Account.find_by!(number: @orca).status
  end

  test "同じ対象は二重に申請できない" do
    request_reversal_as_tama
    sign_in_as_staff @kuro

    post admin_account_reversals_path(@orca), params: { event_id: @entry.event_id, reason: "わたしも", preview: "1" }
    assert_response :unprocessable_entity
    assert_match "すでに承認待ち", response.body
    assert_equal 1, ApprovalRequest.count
  end

  test "利用者のログインでは承認待ちに入れない" do
    request = request_reversal_as_tama
    delete staff_session_path
    orca = create_customer(name: "オルカ")
    orca.grant_account(@orca)
    sign_in_as_customer orca

    get admin_approvals_path
    assert_redirected_to new_staff_session_path
    post admin_approval_grant_path(request)
    assert_redirected_to new_staff_session_path
    post admin_approval_rejection_path(request), params: { reason: "いたずら" }
    assert_redirected_to new_staff_session_path
    assert request.reload.pending?
    assert_equal 100, balance
  end
end
