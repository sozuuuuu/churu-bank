require "test_helper"

# 管理画面と RES Browser には行員しか入れない（利用者のログインでは入れない）
class Admin::AccessTest < ActionDispatch::IntegrationTest
  test "ログインしていなければ行員のログイン画面へ。/res は 404" do
    get admin_accounts_path
    assert_redirected_to new_staff_session_path
    get "/res"
    assert_response :not_found
  end

  test "利用者としてログインしていても、行員のログイン画面へ。/res は 404" do
    sign_in_as_customer create_customer(name: "オルカ")

    get admin_accounts_path
    assert_redirected_to new_staff_session_path
    post admin_accounts_path, params: { holder_name: "いたずら" }
    assert_redirected_to new_staff_session_path
    assert_not Account.exists?(holder_name: "いたずら")
    get "/res"
    assert_response :not_found
  end

  test "行員は全口座の一覧と /res を見られる。ライブ更新は行員用のチャンネル" do
    sign_in_as_staff create_staff
    Banking::Bank.new(actor: "test").open_account(holder_name: "オルカ")

    get admin_accounts_path
    assert_response :success
    assert_match "オルカ", response.body
    assert_no_match "ui/cat", response.body # 利用者画面のねこテーマは読み込まない
    assert_select "turbo-cable-stream-source[channel=StaffStreamsChannel]"
    assert_select "turbo-cable-stream-source[channel='Turbo::StreamsChannel']", count: 0
    get "/res"
    assert_redirected_to "/res/streams/all" # RES Browser の中へ
  end

  test "口座開設で持ち主を選ぶと、その利用者にひも付く" do
    sign_in_as_staff create_staff
    orca = create_customer(name: "オルカ")

    post admin_accounts_path, params: { holder_name: "オルカ", owner_id: orca.id }

    number = Account.find_by!(holder_name: "オルカ").number
    assert_redirected_to admin_account_path(number)
    assert_equal [ number ], orca.account_numbers
  end
end
