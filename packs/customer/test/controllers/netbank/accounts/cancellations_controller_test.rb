require "test_helper"

# 予約振込と、実行前（予約中・保留中）の自分の振込の取消
class Netbank::Accounts::CancellationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @bank = Banking::Bank.new(actor: "test")
    @orca = create_customer(name: "オルカ")
    @orca_number = @bank.open_account(holder_name: "オルカ").account_number
    @orca.grant_account(@orca_number)
    @zingiber_number = @bank.open_account(holder_name: "ジンジベル").account_number
    @bank.deposit(@orca_number, 1000)
    @bank.deposit(@zingiber_number, 1000)
    sign_in_as_customer @orca
  end

  def balance(number) = Account.find_by!(number:).balance
  def tomorrow = (Date.current + 1).iso8601

  test "実行日を入れると、確認 → 確定で予約できて、口座ページに出る" do
    post account_transfers_path(@orca_number), params: { to: @zingiber_number, amount: "40", execute_on: tomorrow, preview: "1" }
    assert_response :success
    assert_match "予約する", response.body
    assert_match "いまはまだ引き落としません", response.body

    post account_transfers_path(@orca_number), params: { to: @zingiber_number, amount: "40", execute_on: tomorrow }
    assert_redirected_to account_path(@orca_number)
    follow_redirect!
    assert_match "振込を予約しました", response.body
    assert_select "#pending-transfers li", 1
    transfer = Transfer.last
    assert_equal [ "scheduled", Date.iso8601(tomorrow), @orca.actor ],
                 [ transfer.status, transfer.execute_on, transfer.actor ]
    assert_equal 1000, balance(@orca_number)
  end

  test "今日・過去の実行日はエラー" do
    post account_transfers_path(@orca_number), params: { to: @zingiber_number, amount: "40", execute_on: Date.current.iso8601, preview: "1" }
    assert_response :unprocessable_entity
    assert_match "明日以降", response.body
  end

  test "予約中の振込を、確認 → 確定で取り消せる" do
    id = @bank.transfer(@orca_number, @zingiber_number, 40, execute_on: Date.current + 1).transfer_id

    get new_account_transfer_cancellation_path(@orca_number, id)
    assert_response :success
    post account_transfer_cancellation_path(@orca_number, id), params: { preview: "1" }
    assert_response :success
    assert_match "まだ取り消していません", response.body
    assert_equal "scheduled", Transfer.find_by!(transfer_id: id).status

    post account_transfer_cancellation_path(@orca_number, id)
    assert_redirected_to account_path(@orca_number)
    transfer = Transfer.find_by!(transfer_id: id)
    assert_equal [ "cancelled", @orca.actor ], [ transfer.status, transfer.cancelled_by ]
    follow_redirect!
    assert_select "#pending-transfers", 0
  end

  test "高額で保留中の振込を取り消すと、お金が戻る" do
    post account_transfers_path(@orca_number), params: { to: @zingiber_number, amount: Banking::Bank.hold_threshold.to_s }
    follow_redirect!
    assert_match "保留中", response.body
    transfer = Transfer.last
    assert_equal "held", transfer.status

    post account_transfer_cancellation_path(@orca_number, transfer), params: { preview: "1" }
    assert_match "引き落とした分が戻ります", response.body
    post account_transfer_cancellation_path(@orca_number, transfer)

    assert_equal "cancelled", transfer.reload.status
    assert_equal 1000, balance(@orca_number)
  end

  test "実行が始まった振込・取り消し済みの振込は取り消せない" do
    id = @bank.transfer(@orca_number, @zingiber_number, 40).transfer_id

    post account_transfer_cancellation_path(@orca_number, id)
    assert_response :unprocessable_entity
    assert_match "実行が始まっている", response.body

    scheduled = @bank.transfer(@orca_number, @zingiber_number, 40, execute_on: Date.current + 1).transfer_id
    post account_transfer_cancellation_path(@orca_number, scheduled)
    post account_transfer_cancellation_path(@orca_number, scheduled)
    assert_response :unprocessable_entity
    assert_match "取消済み", response.body
  end

  test "他人の振込は取り消せない（404）" do
    id = @bank.transfer(@zingiber_number, @orca_number, 40, execute_on: Date.current + 1).transfer_id

    get new_account_transfer_cancellation_path(@zingiber_number, id)
    assert_response :not_found
    post account_transfer_cancellation_path(@orca_number, id)
    assert_response :not_found
    assert_equal "scheduled", Transfer.find_by!(transfer_id: id).status
  end
end
