require "test_helper"

# 出金の依頼（窓口取引、TODO の Q1）: 利用者は依頼を出すだけ。行員が処理する前なら取り消せる
class Netbank::Accounts::WithdrawalRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bank = Banking::Bank.new(actor: "test")
    @orca = create_customer(name: "オルカ")
    @orca_number = @bank.open_account(holder_name: "オルカ").account_number
    @orca.grant_account(@orca_number)
    @zingiber_number = @bank.open_account(holder_name: "ジンジベル").account_number
    @bank.deposit(@orca_number, 100)
    @bank.deposit(@zingiber_number, 100)
    sign_in_as_customer @orca
  end

  def balance(number) = Account.find_by!(number:).balance

  test "口座ページに出金の依頼のカードがあり、確認 → 確定で依頼を出す。お金はまだ動かない" do
    get account_path(@orca_number)
    assert_select "#withdrawal-requests turbo-frame#withdrawal_request[src=?]", new_account_withdrawal_request_path(@orca_number)

    post account_withdrawal_requests_path(@orca_number), params: { amount: "30", memo: "おやつ", preview: "1" }
    assert_response :success
    assert_match "まだ依頼していません", response.body
    assert_match "WithdrawalRequested", response.body
    assert_empty WithdrawalRequest.all

    post account_withdrawal_requests_path(@orca_number), params: { amount: "30", memo: "おやつ" }
    assert_redirected_to account_path(@orca_number)
    request = WithdrawalRequest.sole
    assert_equal [ "requested", 30, "おやつ", @orca.actor ], [ request.status, request.amount, request.memo, request.requested_by ]
    assert_equal 100, balance(@orca_number)

    follow_redirect!
    assert_select "##{dom_id(request)}", /受付中/
    assert_select "##{dom_id(request)} button", "取り消す"
  end

  test "残高が足りない・金額が数字でなければエラー" do
    post account_withdrawal_requests_path(@orca_number), params: { amount: "101", preview: "1" }
    assert_response :unprocessable_entity
    assert_match "残高不足", response.body

    post account_withdrawal_requests_path(@orca_number), params: { amount: "abc" }
    assert_response :unprocessable_entity
    assert_match "1以上の整数", response.body
  end

  test "行員が処理する前なら取り消せる。処理したあとは取り消せない" do
    request_id = Banking::Bank.new(actor: @orca.actor).request_withdrawal(@orca_number, 30).request_id
    delete account_withdrawal_request_path(@orca_number, request_id)
    assert_redirected_to account_path(@orca_number)
    assert_equal "cancelled", WithdrawalRequest.find_by!(request_id:).status

    processed = Banking::Bank.new(actor: @orca.actor).request_withdrawal(@orca_number, 30).request_id
    Banking::Bank.new(actor: "staff:1").process_withdrawal(processed)
    delete account_withdrawal_request_path(@orca_number, processed)
    assert_match "出金済み", flash[:alert]
    assert_equal 70, balance(@orca_number)
  end

  test "処理されたら通帳に出金の行、断られたら理由が出る" do
    processed = Banking::Bank.new(actor: @orca.actor).request_withdrawal(@orca_number, 30).request_id
    Banking::Bank.new(actor: "staff:1").process_withdrawal(processed)
    rejected = Banking::Bank.new(actor: @orca.actor).request_withdrawal(@orca_number, 10).request_id
    Banking::Bank.new(actor: "staff:1").reject_withdrawal(rejected, reason: "本人確認ができません")

    get account_path(@orca_number)
    assert_select "#withdrawal-requests li", /出金済み/
    assert_select "#withdrawal-requests li", /お断り.*本人確認ができません/m
    assert_select ".passbook li", /出金/
  end

  test "他人の口座では依頼も取消もできない（404）" do
    post account_withdrawal_requests_path(@zingiber_number), params: { amount: "10" }
    assert_response :not_found

    request_id = Banking::Bank.new(actor: "customer:other").request_withdrawal(@zingiber_number, 10).request_id
    delete account_withdrawal_request_path(@zingiber_number, request_id)
    assert_response :not_found
    delete account_withdrawal_request_path(@orca_number, request_id) # 自分の口座の URL に他人の依頼
    assert_response :not_found
    assert WithdrawalRequest.find_by!(request_id:).open?
    assert_equal 100, balance(@zingiber_number)
  end
end
