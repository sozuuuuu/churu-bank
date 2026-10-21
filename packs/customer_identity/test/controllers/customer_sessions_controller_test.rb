require "test_helper"

class CustomerSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @customer = create_customer(name: "オルカ")
  end

  test "利用者のログイン画面（/session/new）はねこテーマ。行員の画面へのリンクはない" do
    get new_customer_session_path
    assert_response :success
    assert_equal "/session/new", new_customer_session_path
    assert_match "ui/cat", response.body
    assert_no_match "/admin", response.body
  end

  test "ログインすると利用者画面へ。Cookie は customer_session_id" do
    post customer_session_path, params: { email_address: @customer.email_address, password: TEST_PASSWORD }

    assert_redirected_to root_url
    assert cookies[:customer_session_id].present?
    assert_nil cookies[:staff_session_id]
  end

  test "ログインしていなければ利用者のログイン画面へ。ログイン後は元のページへ戻る" do
    get accounts_path
    assert_redirected_to new_customer_session_path

    post customer_session_path, params: { email_address: @customer.email_address, password: TEST_PASSWORD }
    assert_redirected_to accounts_url
  end

  test "行員のアカウントでは利用者としてログインできない" do
    staff = create_staff

    post customer_session_path, params: { email_address: staff.email_address, password: TEST_PASSWORD }

    assert_redirected_to new_customer_session_path
    assert_nil cookies[:customer_session_id]
  end

  test "ログアウト" do
    sign_in_as_customer @customer

    delete customer_session_path

    assert_redirected_to new_customer_session_path
    assert_empty cookies[:customer_session_id]
    get root_path
    assert_redirected_to new_customer_session_path
  end
end
