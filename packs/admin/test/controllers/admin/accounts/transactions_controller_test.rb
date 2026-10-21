require "test_helper"

class Admin::Accounts::TransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as_staff(@admin = create_staff)
    @number = Banking::Bank.new(actor: "test").open_account(holder_name: "オルカ").account_number
  end

  test "確認（preview）では記帳されず、確定で記帳される" do
    post admin_account_transactions_path(@number), params: { amount: "100", preview: "1" }
    assert_response :success
    assert_match "まだ記帳していません", response.body
    assert_equal 0, Account.find_by!(number: @number).balance

    post admin_account_transactions_path(@number), params: { amount: "100" }
    assert_redirected_to admin_account_path(@number)
    assert_equal 100, Account.find_by!(number: @number).balance
    assert_equal @admin.actor, LedgerEntry.last.actor
  end

  test "入金（現金の持ち込み）だけ。出金のフォームはない（出金は窓口の出金依頼から）" do
    get new_admin_account_transaction_path(@number)

    assert_select "turbo-frame#transaction input[name=amount]"
    assert_select "input[type=radio]", count: 0
    assert_no_match "出金", response.body
  end

  test "金額が数字でなければエラー" do
    post admin_account_transactions_path(@number), params: { amount: "abc" }

    assert_response :unprocessable_entity
    assert_match "1以上の整数", response.body
  end
end
