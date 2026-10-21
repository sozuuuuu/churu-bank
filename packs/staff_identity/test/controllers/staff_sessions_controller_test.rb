require "test_helper"

class StaffSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @staff = create_staff
  end

  test "行員のログイン画面（/admin/session/new）。ねこテーマではない" do
    get new_staff_session_path
    assert_response :success
    assert_equal "/admin/session/new", new_staff_session_path
    assert_select "h1", "行員ログイン"
    assert_no_match "ui/cat", response.body
  end

  test "ログインすると管理画面へ。Cookie は staff_session_id" do
    post staff_session_path, params: { email_address: @staff.email_address, password: TEST_PASSWORD }

    assert_redirected_to admin_root_url
    assert cookies[:staff_session_id].present?
    assert_nil cookies[:customer_session_id]
  end

  test "ログインしていなければ行員のログイン画面へ。ログイン後は元のページへ戻る" do
    get admin_transfers_path
    assert_redirected_to new_staff_session_path

    post staff_session_path, params: { email_address: @staff.email_address, password: TEST_PASSWORD }
    assert_redirected_to admin_transfers_url
  end

  test "利用者のアカウントでは行員としてログインできない" do
    customer = create_customer(name: "オルカ")

    post staff_session_path, params: { email_address: customer.email_address, password: TEST_PASSWORD }

    assert_redirected_to new_staff_session_path
    assert_nil cookies[:staff_session_id]
  end

  test "パスワードが違えばログインできない" do
    post staff_session_path, params: { email_address: @staff.email_address, password: "wrong" }

    assert_redirected_to new_staff_session_path
    assert_nil cookies[:staff_session_id]
  end

  test "ログアウト" do
    sign_in_as_staff @staff

    delete staff_session_path

    assert_redirected_to new_staff_session_path
    assert_empty cookies[:staff_session_id]
    get admin_root_path
    assert_redirected_to new_staff_session_path
  end
end
