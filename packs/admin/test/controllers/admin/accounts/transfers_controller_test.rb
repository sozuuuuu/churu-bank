require "test_helper"

class Admin::Accounts::TransfersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as_staff(@admin = create_staff)
    bank = Banking::Bank.new(actor: "test")
    @orca = bank.open_account(holder_name: "オルカ").account_number
    @zingiber = bank.open_account(holder_name: "ジンジベル").account_number
    bank.deposit(@orca, 100)
  end

  test "確認では振り込まれず、確定で受け付けられ、ジョブで入金される" do
    post admin_account_transfers_path(@orca), params: { to: @zingiber, amount: "40", preview: "1" }
    assert_response :success
    assert_match "まだ振り込んでいません", response.body
    assert_equal 0, Transfer.count

    post admin_account_transfers_path(@orca), params: { to: @zingiber, amount: "40" }
    assert_redirected_to admin_account_path(@orca)
    assert_equal "requested", Transfer.last.status

    perform_enqueued_jobs # 振込の後半は銀行パックの中のジョブ。画面からは名指ししない
    assert_equal "completed", Transfer.last.status
    assert_equal 40, Account.find_by!(number: @zingiber).balance
  end

  test "凍結中の口座への振込は、確認画面で組戻しになると警告する" do
    post admin_account_freeze_path(@zingiber)
    assert_equal "frozen", Account.find_by!(number: @zingiber).status

    post admin_account_transfers_path(@orca), params: { to: @zingiber, amount: "40", preview: "1" }
    assert_match "組戻し", response.body

    # 解除は二人承認なので、申請しただけでは凍結のまま
    delete admin_account_freeze_path(@zingiber), params: { reason: "確認できた" }
    assert_equal "frozen", Account.find_by!(number: @zingiber).status
    assert ApprovalRequest.pending.exists?(kind: "unfreeze", account_number: @zingiber)
  end

  test "振込先を選ばないとエラー" do
    post admin_account_transfers_path(@orca), params: { amount: "40", preview: "1" }

    assert_response :unprocessable_entity
    assert_match "振込先を選んでください", response.body
  end

  test "振込一覧と口座ページに状態が出る" do
    post admin_account_transfers_path(@orca), params: { to: @zingiber, amount: "40", memo: "おやつ代" }

    get admin_transfers_path
    assert_match "処理中", response.body
    get admin_account_path(@orca)
    assert_match "振込（送金）", response.body
    assert_match "ジンジベル", response.body
  end
end
