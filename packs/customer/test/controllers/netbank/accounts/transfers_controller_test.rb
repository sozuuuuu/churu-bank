require "test_helper"

class Netbank::Accounts::TransfersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    bank = Banking::Bank.new(actor: "test")
    @orca = create_customer(name: "オルカ")
    @orca_number = bank.open_account(holder_name: "オルカ").account_number
    @orca.grant_account(@orca_number)
    @zingiber_number = bank.open_account(holder_name: "ジンジベル").account_number
    bank.deposit(@orca_number, 100)
    bank.deposit(@zingiber_number, 100)
    sign_in_as_customer @orca
  end

  test "自分の口座から、確認 → 確定で振り込める" do
    post account_transfers_path(@orca_number), params: { to: @zingiber_number, amount: "40", preview: "1" }
    assert_response :success
    assert_match "まだ振り込んでいません", response.body
    assert_equal 0, Transfer.count

    post account_transfers_path(@orca_number), params: { to: @zingiber_number, amount: "40" }
    assert_redirected_to account_path(@orca_number)
    assert_equal @orca.actor, LedgerEntry.where(account_number: @orca_number).last.actor

    perform_enqueued_jobs
    assert_equal "completed", Transfer.last.status
    assert_equal 140, Account.find_by!(number: @zingiber_number).balance
  end

  test "他人の口座からは振り込めない（404 で、お金も動かない）" do
    get new_account_transfer_path(@zingiber_number)
    assert_response :not_found

    post account_transfers_path(@zingiber_number), params: { to: @orca_number, amount: "40" }
    assert_response :not_found
    assert_equal 100, Account.find_by!(number: @zingiber_number).balance
    assert_equal 0, Transfer.count
  end

  test "凍結中の自分の口座からは振り込めない" do
    Banking::Bank.new(actor: "test").freeze_account(@orca_number, reason: "テスト")

    post account_transfers_path(@orca_number), params: { to: @zingiber_number, amount: "40", preview: "1" }

    assert_response :unprocessable_entity
    assert_match "凍結中", response.body
  end

  test "入出金は利用者画面にはない" do
    assert_raises(NoMethodError) { account_transactions_path(@orca_number) }
  end
end
