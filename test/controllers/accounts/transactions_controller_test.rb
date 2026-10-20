require "test_helper"

class Accounts::TransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @number = Banking::Bank.new(actor: "test").open_account(holder_name: "オルカ").account_number
  end

  test "確認（preview）では記帳されず、確定で記帳される" do
    post account_transactions_path(@number), params: { kind: "deposit", amount: "100", preview: "1" }
    assert_response :success
    assert_match "まだ記帳していません", response.body
    assert_equal 0, Account.find_by!(number: @number).balance

    post account_transactions_path(@number), params: { kind: "deposit", amount: "100" }
    assert_redirected_to account_path(@number)
    assert_equal 100, Account.find_by!(number: @number).balance
    assert_equal "web", LedgerEntry.last.actor
  end

  test "残高不足は入力画面に戻ってエラーを出す" do
    post account_transactions_path(@number), params: { kind: "withdrawal", amount: "1", preview: "1" }

    assert_response :unprocessable_entity
    assert_match "残高不足", response.body
  end

  test "金額が数字でなければエラー" do
    post account_transactions_path(@number), params: { kind: "deposit", amount: "abc" }

    assert_response :unprocessable_entity
    assert_match "1以上の整数", response.body
  end
end
