require "test_helper"

class Customer::AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    bank = Banking::Bank.new(actor: "test")
    @orca = create_user(name: "オルカ")
    @orca_number = bank.open_account(holder_name: "オルカ").account_number
    @orca.grant_account(@orca_number)
    @zingiber_number = bank.open_account(holder_name: "ジンジベル").account_number
    bank.deposit(@orca_number, 120)
    sign_in_as @orca
  end

  test "一覧には自分の口座だけ出る" do
    get root_path

    assert_response :success
    assert_match @orca_number, response.body
    assert_no_match @zingiber_number, response.body
  end

  test "自分の口座ページでは残高と通帳が見られる" do
    get account_path(@orca_number)

    assert_response :success
    assert_match "120 ちゅ〜る", response.body
    assert_match "turbo-cable-stream-source", response.body # ライブ更新を購読している
    assert_match "customer/theme", response.body # 利用者画面のテーマ
    assert_match 'data-controller="count-up"', response.body # 残高のカウントアップ
  end

  test "他人の口座は口座ページも時点残高も 404" do
    get account_path(@zingiber_number)
    assert_response :not_found

    get balance_account_path(@zingiber_number, date: Date.current), headers: { "Turbo-Frame" => "balance" }
    assert_response :not_found
  end

  test "時点指定の残高（Turbo Frame）" do
    get balance_account_path(@orca_number, date: Date.current), headers: { "Turbo-Frame" => "balance" }

    assert_response :success
    assert_match "起算日基準", response.body
  end
end
