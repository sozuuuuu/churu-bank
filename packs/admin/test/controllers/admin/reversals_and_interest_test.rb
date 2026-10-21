require "test_helper"

# 管理画面の取消・組戻し・利息の手動実行（どれも確認 → 確定の2段階）
class Admin::ReversalsAndInterestTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as_staff(@admin = create_staff)
    @bank = Banking::Bank.new(actor: "test")
    @orca = @bank.open_account(holder_name: "オルカ").account_number
    @zingiber = @bank.open_account(holder_name: "ジンジベル").account_number
  end

  test "入金の取消: 確認では何も起きず、確定で逆仕訳が入り、通帳で対応が分かる" do
    @bank.deposit(@orca, 100, memo: "おこづかい")
    entry = LedgerEntry.find_by!(account_number: @orca, kind: "deposit")

    get admin_account_path(@orca)
    assert_select "a[href=?]", new_admin_account_reversal_path(@orca, event_id: entry.event_id), text: "取消"

    get new_admin_account_reversal_path(@orca, event_id: entry.event_id)
    assert_select "turbo-frame#reversal input[name=reason]"

    post admin_account_reversals_path(@orca), params: { event_id: entry.event_id, reason: "金額まちがい", preview: "1" }
    assert_response :success
    assert_match "まだ取り消していません", response.body
    assert_match "DepositReversed", response.body
    assert_equal 100, Account.find_by!(number: @orca).balance

    post admin_account_reversals_path(@orca), params: { event_id: entry.event_id, reason: "金額まちがい" }
    assert_redirected_to admin_account_path(@orca)
    assert_equal 0, Account.find_by!(number: @orca).balance
    assert entry.reload.reversed?

    get admin_account_path(@orca)
    assert_select "tr.reversed##{dom_id(entry)}" do
      assert_select ".badge-reversed", "取消済み"
      assert_select "a.button", text: "取消", count: 0
    end
    assert_select "tr.reversal a[href=?]", "##{dom_id(entry)}"
  end

  test "取消の理由が空ならエラー、取消済みの行にはフォームを出さない" do
    @bank.deposit(@orca, 100)
    entry = LedgerEntry.find_by!(account_number: @orca, kind: "deposit")

    post admin_account_reversals_path(@orca), params: { event_id: entry.event_id, reason: " ", preview: "1" }
    assert_response :unprocessable_entity
    assert_match "取消の理由を入れてください", response.body

    @bank.reverse(@orca, entry.event_id, reason: "テスト", approval: approval_for_test)
    get new_admin_account_reversal_path(@orca, event_id: entry.event_id)
    assert_match "この取引は取り消せません", response.body
    assert_select "input[name=reason]", count: 0
  end

  test "振込の組戻し: 振込一覧から確認 → 確定で両方の残高が戻り、口座ページへ戻れる" do
    @bank.deposit(@orca, 100)
    @bank.transfer(@orca, @zingiber, 40)
    perform_enqueued_jobs
    transfer = Transfer.last
    assert_equal "completed", transfer.status

    get admin_transfers_path
    assert_select "a[href=?]", new_admin_transfer_reversal_path(transfer), text: "組戻し"
    get admin_account_path(@zingiber)
    assert_select "a[href=?]", new_admin_transfer_reversal_path(transfer, back_to: @zingiber), text: "組戻し"

    post admin_transfer_reversals_path(transfer), params: { reason: "振込先まちがい", back_to: @zingiber, preview: "1" }
    assert_response :success
    assert_match "まだ組戻ししていません", response.body
    assert_match "TransferReversed", response.body
    assert_equal 40, Account.find_by!(number: @zingiber).balance

    post admin_transfer_reversals_path(transfer), params: { reason: "振込先まちがい", back_to: @zingiber }
    assert_redirected_to admin_account_path(@zingiber)
    assert_equal "reversed", transfer.reload.status
    assert_equal 100, Account.find_by!(number: @orca).balance
    assert_equal 0, Account.find_by!(number: @zingiber).balance

    get admin_transfers_path
    assert_match "振込先まちがい", response.body
    assert_select "a", text: "組戻し", count: 0
  end

  test "処理中の振込は組戻しできない" do
    @bank.deposit(@orca, 100)
    @bank.transfer(@orca, @zingiber, 40)

    get new_admin_transfer_reversal_path(Transfer.last)
    assert_match "完了した振込だけ", response.body
  end

  test "利息（全口座）: 確認で口座ごとの額を出し、確定で払う。2回目は何もしない" do
    @bank.deposit(@orca, 1000, value_date: Date.current - 2) # 1日 0.1% → 1
    date = Date.yesterday

    get admin_interest_path
    assert_match "36.5%", response.body

    post admin_interest_path, params: { date: date.iso8601, preview: "1" }
    assert_response :success
    assert_select "table.interest-rows tr", text: /オルカ.*\+1/m
    assert_match "残高が 0 なので払いません", response.body # ジンジベル
    assert_equal 1000, Account.find_by!(number: @orca).balance

    post admin_interest_path, params: { date: date.iso8601 }
    assert_redirected_to admin_interest_path(date:)
    assert_match "1 口座に払いました", flash[:notice]
    assert_equal 1001, Account.find_by!(number: @orca).balance
    get admin_interest_path(date:) # flash が morph で消えても、状況は URL の日付から出る
    assert_select ".interest-status", /支払い済み\s*1\s*口座.*まだ払っていない\s*0\s*口座/m

    post admin_interest_path, params: { date: date.iso8601, preview: "1" }
    assert_match "支払い済み", response.body
    assert_match "確定しても何も起きません", response.body
    assert_select "input[type=submit][value=?]", "この日の利息を払う", count: 0

    post admin_interest_path, params: { date: date.iso8601 }
    assert_match "何もしませんでした", flash[:alert]
    assert_equal 1001, Account.find_by!(number: @orca).balance
  end

  test "利息（1口座）: 口座ページの Frame から払える。今日以降は選べない" do
    @bank.deposit(@orca, 1000, value_date: Date.current - 2)

    get new_admin_account_interest_path(@orca)
    assert_select "turbo-frame#interest input[type=date]"

    post admin_account_interest_path(@orca), params: { date: Date.current.iso8601, preview: "1" }
    assert_response :unprocessable_entity
    assert_match "まだ終わっていない日", response.body

    post admin_account_interest_path(@orca), params: { date: Date.yesterday.iso8601 }
    assert_redirected_to admin_account_path(@orca)
    assert_equal 1001, Account.find_by!(number: @orca).balance
    assert_equal 0, Account.find_by!(number: @zingiber).balance

    post admin_account_interest_path(@orca), params: { date: Date.yesterday.iso8601 }
    assert_match "何もしませんでした", flash[:alert]
  end

  test "利用者のログインでは、どの URL も行員のログイン画面へ飛ばされ、何も書き込まれない" do
    @bank.deposit(@orca, 1000, value_date: Date.current - 2)
    @bank.transfer(@orca, @zingiber, 40)
    perform_enqueued_jobs
    entry = LedgerEntry.find_by!(account_number: @orca, kind: "deposit")
    transfer = Transfer.last

    orca = create_customer(name: "オルカ")
    orca.grant_account(@orca)
    delete staff_session_path # setup の行員のログインを終えてから
    sign_in_as_customer orca

    get new_admin_account_reversal_path(@orca, event_id: entry.event_id)
    assert_redirected_to new_staff_session_path
    post admin_account_reversals_path(@orca), params: { event_id: entry.event_id, reason: "いたずら" }
    assert_redirected_to new_staff_session_path
    get new_admin_transfer_reversal_path(transfer)
    assert_redirected_to new_staff_session_path
    post admin_transfer_reversals_path(transfer), params: { reason: "いたずら" }
    assert_redirected_to new_staff_session_path
    get admin_interest_path
    assert_redirected_to new_staff_session_path
    post admin_interest_path, params: { date: Date.yesterday.iso8601 }
    assert_redirected_to new_staff_session_path
    get new_admin_account_interest_path(@orca)
    assert_redirected_to new_staff_session_path
    post admin_account_interest_path(@orca), params: { date: Date.yesterday.iso8601 }
    assert_redirected_to new_staff_session_path

    assert_not entry.reload.reversed?
    assert_equal "completed", transfer.reload.status
    assert_equal 960, Account.find_by!(number: @orca).balance
  end
end
