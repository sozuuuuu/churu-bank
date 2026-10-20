require "test_helper"

class Accounts::TransfersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    bank = Banking::Bank.new(actor: "test")
    @orca = bank.open_account(holder_name: "オルカ").account_number
    @zingiber = bank.open_account(holder_name: "ジンジベル").account_number
    bank.deposit(@orca, 100)
  end

  test "確認では振り込まれず、確定で受け付けられ、ジョブで入金される" do
    post account_transfers_path(@orca), params: { to: @zingiber, amount: "40", preview: "1" }
    assert_response :success
    assert_match "まだ振り込んでいません", response.body
    assert_equal 0, Transfer.count

    post account_transfers_path(@orca), params: { to: @zingiber, amount: "40" }
    assert_redirected_to account_path(@orca)
    assert_equal "requested", Transfer.last.status

    perform_enqueued_jobs(only: Transfers::SettleJob)
    assert_equal "completed", Transfer.last.status
    assert_equal 40, Account.find_by!(number: @zingiber).balance
  end

  test "凍結中の口座への振込は、確認画面で組戻しになると警告する" do
    post account_freeze_path(@zingiber)
    assert_equal "frozen", Account.find_by!(number: @zingiber).status

    post account_transfers_path(@orca), params: { to: @zingiber, amount: "40", preview: "1" }
    assert_match "組戻し", response.body

    delete account_freeze_path(@zingiber)
    assert_equal "active", Account.find_by!(number: @zingiber).status
  end

  test "振込先を選ばないとエラー" do
    post account_transfers_path(@orca), params: { amount: "40", preview: "1" }

    assert_response :unprocessable_entity
    assert_match "振込先を選んでください", response.body
  end

  test "振込一覧と口座ページに状態が出る" do
    post account_transfers_path(@orca), params: { to: @zingiber, amount: "40", memo: "おやつ代" }

    get transfers_path
    assert_match "処理中", response.body
    get account_path(@orca)
    assert_match "振込（送金）", response.body
    assert_match "ジンジベル", response.body
  end
end
