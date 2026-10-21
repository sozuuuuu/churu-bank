require "test_helper"

# 管理画面と RES Browser には管理者しか入れない
class Admin::AccessTest < ActionDispatch::IntegrationTest
  test "ログインしていなければログイン画面へ" do
    get admin_accounts_path
    assert_redirected_to new_session_path
  end

  test "利用者には管理画面も /res も 404" do
    sign_in_as create_user(name: "オルカ")

    get admin_accounts_path
    assert_response :not_found
    get "/res"
    assert_response :not_found
  end

  test "管理者は全口座の一覧と /res を見られる" do
    sign_in_as create_user(name: "行員", admin: true)
    Banking::Bank.new(actor: "test").open_account(holder_name: "オルカ")

    get admin_accounts_path
    assert_response :success
    assert_match "オルカ", response.body
    assert_no_match "ui/cat", response.body # 利用者画面のねこテーマは読み込まない
    get "/res"
    assert_redirected_to "/res/streams/all" # RES Browser の中へ
  end

  test "口座開設で持ち主を選ぶと、その利用者にひも付く" do
    sign_in_as create_user(name: "行員", admin: true)
    orca = create_user(name: "オルカ")

    post admin_accounts_path, params: { holder_name: "オルカ", owner_id: orca.id }

    number = Account.find_by!(holder_name: "オルカ").number
    assert_redirected_to admin_account_path(number)
    assert_equal [ number ], orca.account_numbers
  end
end
