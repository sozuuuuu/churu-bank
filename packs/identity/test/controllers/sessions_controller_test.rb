require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "オルカ")
    @admin = create_user(name: "行員", admin: true)
  end

  test "ログイン画面" do
    get new_session_path
    assert_response :success
  end

  test "利用者はログインすると利用者画面へ" do
    post session_path, params: { email_address: @user.email_address, password: TEST_PASSWORD }

    assert_redirected_to root_url
    assert cookies[:session_id]
  end

  test "管理者はログインすると管理画面へ" do
    post session_path, params: { email_address: @admin.email_address, password: TEST_PASSWORD }

    assert_redirected_to admin_root_url
  end

  test "ログインしていなければログイン画面へ。ログイン後は元のページへ戻る" do
    get accounts_path
    assert_redirected_to new_session_path

    post session_path, params: { email_address: @user.email_address, password: TEST_PASSWORD }
    assert_redirected_to accounts_url
  end

  test "パスワードが違えばログインできない" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "ログアウト" do
    sign_in_as(@user)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end
end
