require "test_helper"

# 行員: 保留中の振込を通す・実行前（予約中・保留中）の振込を差し止める
class Admin::TransferHoldsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @bank = Banking::Bank.new(actor: "test")
    @orca = @bank.open_account(holder_name: "オルカ").account_number
    @zingiber = @bank.open_account(holder_name: "ジンジベル").account_number
    @bank.deposit(@orca, 1000)
    @threshold = Banking::Bank.hold_threshold
    @admin = create_user(name: "行員", admin: true)
    sign_in_as @admin
  end

  def balance(number) = Account.find_by!(number:).balance

  test "振込一覧の保留中の振込に「通す」「差し止める」、予約中には「差し止める」だけ" do
    held = @bank.transfer(@orca, @zingiber, @threshold).transfer_id
    scheduled = @bank.transfer(@orca, @zingiber, 10, execute_on: Date.current + 1).transfer_id

    get admin_transfers_path
    assert_select "a[href='#{new_admin_transfer_release_path(held)}']", 1
    assert_select "a[href='#{new_admin_transfer_stop_path(held)}']", 1
    assert_select "a[href='#{new_admin_transfer_release_path(scheduled)}']", 0
    assert_select "a[href='#{new_admin_transfer_stop_path(scheduled)}']", 1
    assert_match "保留中の振込が 1 件", response.body
  end

  test "確認 → 確定で保留を通すと、入金されて完了する" do
    id = @bank.transfer(@orca, @zingiber, @threshold).transfer_id

    get new_admin_transfer_release_path(id)
    assert_response :success
    post admin_transfer_release_path(id), params: { preview: "1" }
    assert_match "まだ通していません", response.body
    assert_equal "held", Transfer.find_by!(transfer_id: id).status

    post admin_transfer_release_path(id)
    assert_redirected_to admin_transfers_path
    perform_enqueued_jobs
    assert_equal "completed", Transfer.find_by!(transfer_id: id).status
    assert_equal @threshold, balance(@zingiber)

    post admin_transfer_release_path(id)
    assert_response :unprocessable_entity
  end

  test "確認 → 確定で差し止めると、振込元へ戻る。理由がなければエラー" do
    id = @bank.transfer(@orca, @zingiber, @threshold).transfer_id

    post admin_transfer_stop_path(id), params: { reason: "", preview: "1" }
    assert_response :unprocessable_entity
    post admin_transfer_stop_path(id), params: { reason: "詐欺の疑い", preview: "1" }
    assert_match "引き落とした分を戻します", response.body

    post admin_transfer_stop_path(id), params: { reason: "詐欺の疑い" }
    assert_redirected_to admin_transfers_path
    transfer = Transfer.find_by!(transfer_id: id)
    assert_equal [ "stopped", "詐欺の疑い", "admin:#{@admin.email_address}" ],
                 [ transfer.status, transfer.cancel_reason, transfer.cancelled_by ]
    assert_equal 1000, balance(@orca)
    perform_enqueued_jobs
    assert_equal 0, balance(@zingiber)
  end

  test "予約中の振込を差し止めると、実行日になっても実行されない" do
    id = @bank.transfer(@orca, @zingiber, 10, execute_on: Date.current + 1).transfer_id

    post admin_transfer_stop_path(id), params: { reason: "名義の確認" }
    @bank.execute_due_transfers(date: Date.current + 1)

    assert_equal "stopped", Transfer.find_by!(transfer_id: id).status
    assert_equal 1000, balance(@orca)
  end

  test "実行が始まった振込は差し止められない" do
    id = @bank.transfer(@orca, @zingiber, 10).transfer_id

    get new_admin_transfer_stop_path(id)
    assert_match "差し止められるのは", response.body
    post admin_transfer_stop_path(id), params: { reason: "念のため" }
    assert_response :unprocessable_entity
    assert_match "実行が始まっている", response.body
  end

  test "利用者には見えない（404）" do
    id = @bank.transfer(@orca, @zingiber, @threshold).transfer_id
    sign_in_as create_user(name: "オルカ")

    post admin_transfer_release_path(id)
    assert_response :not_found
    post admin_transfer_stop_path(id), params: { reason: "x" }
    assert_response :not_found
    assert_equal "held", Transfer.find_by!(transfer_id: id).status
  end
end
