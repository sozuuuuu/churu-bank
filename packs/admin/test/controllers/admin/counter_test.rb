require "test_helper"

# 窓口（TODO の Q1）: 行員は利用者の出金依頼があるときだけ出金できる。処理（出金）か、理由をつけて断る
class Admin::CounterTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as_staff(@tama = create_staff(name: "たま"))
    @bank = Banking::Bank.new(actor: "test")
    @orca = @bank.open_account(holder_name: "オルカ").account_number
    @bank.deposit(@orca, 100)
    @request_id = Banking::Bank.new(actor: "customer:1").request_withdrawal(@orca, 30, memo: "おやつ").request_id
  end

  def balance = Account.find_by!(number: @orca).balance

  test "窓口に受付中の依頼が並ぶ。メニューに件数" do
    get admin_withdrawal_requests_path
    assert_response :success
    assert_select "nav a[href=?] .badge", admin_withdrawal_requests_path, "1"
    assert_select "tr#withdrawal_request_#{WithdrawalRequest.sole.id}", /オルカ.*30 ちゅ〜る.*おやつ/m
    assert_select "turbo-cable-stream-source[channel=StaffStreamsChannel]"
  end

  test "出金する: 確認では何も起きず、確定で出金。二重には出金しない" do
    get new_admin_withdrawal_request_processing_path(@request_id)
    assert_select "turbo-frame#counter", /100 ちゅ〜る → .*70 ちゅ〜る/m
    assert_select "input[type=submit][value=?]", "出金を確定する"
    assert_equal 100, balance

    post admin_withdrawal_request_processing_path(@request_id)
    assert_redirected_to admin_withdrawal_requests_path
    assert_equal 70, balance
    request = WithdrawalRequest.sole
    assert_equal [ "processed", @tama.actor ], [ request.status, request.closed_by ]
    assert_equal @tama.actor, LedgerEntry.last.actor

    post admin_withdrawal_request_processing_path(@request_id)
    assert_response :unprocessable_entity
    assert_match "出金済みなので処理できません", response.body
    assert_equal 70, balance
  end

  test "断る: 理由は必須。確認 → 確定で断り、お金は動かない" do
    post admin_withdrawal_request_rejection_path(@request_id), params: { reason: " ", preview: "1" }
    assert_response :unprocessable_entity
    assert_match "断る理由を入れてください", response.body

    post admin_withdrawal_request_rejection_path(@request_id), params: { reason: "本人確認ができません", preview: "1" }
    assert_match "まだ断っていません", response.body
    assert WithdrawalRequest.sole.open?

    post admin_withdrawal_request_rejection_path(@request_id), params: { reason: "本人確認ができません" }
    assert_redirected_to admin_withdrawal_requests_path
    assert_equal [ "rejected", "本人確認ができません" ], WithdrawalRequest.sole.then { [ it.status, it.reject_reason ] }
    assert_equal 100, balance

    get new_admin_withdrawal_request_processing_path(@request_id)
    assert_match "お断り", response.body
    assert_select "input[type=submit][value=?]", "出金を確定する", count: 0
  end

  test "利用者が取り消した依頼は出金できない" do
    Banking::Bank.new(actor: "customer:1").cancel_withdrawal(@request_id)

    post admin_withdrawal_request_processing_path(@request_id)
    assert_response :unprocessable_entity
    assert_match "取消済み", response.body
    assert_equal 100, balance
  end

  test "口座ページに依頼なしで出金するフォームはない。依頼があれば窓口へのリンク" do
    get admin_account_path(@orca)
    assert_select "h2", "入金（現金の持ち込み）"
    assert_select "h2", "窓口の出金依頼"
    assert_select "a[href=?]", admin_withdrawal_requests_path, text: "窓口で処理する"
  end

  test "利用者のログインでは窓口に入れない" do
    delete staff_session_path
    orca = create_customer(name: "オルカ")
    orca.grant_account(@orca)
    sign_in_as_customer orca

    get admin_withdrawal_requests_path
    assert_redirected_to new_staff_session_path
    post admin_withdrawal_request_processing_path(@request_id)
    assert_redirected_to new_staff_session_path
    post admin_withdrawal_request_rejection_path(@request_id), params: { reason: "いたずら" }
    assert_redirected_to new_staff_session_path
    assert WithdrawalRequest.sole.open?
    assert_equal 100, balance
  end
end
