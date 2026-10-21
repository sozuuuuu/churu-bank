require "test_helper"

class StaffSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @staff = create_staff(name: "たま")
  end

  test "行員のログイン画面（/admin/session/new）は行員を選ぶドロップダウン。パスワードはない。ねこテーマではない" do
    other = create_staff(name: "くろ")

    get new_staff_session_path
    assert_response :success
    assert_equal "/admin/session/new", new_staff_session_path
    assert_select "h1", "行員ログイン"
    assert_select "select[name=staff_id] option[value='#{@staff.id}']", "たま"
    assert_select "select[name=staff_id] option[value='#{other.id}']", "くろ"
    assert_select "input[type=password]", count: 0
    assert_no_match "ui/cat", response.body
  end

  test "行員を選んで入ると管理画面へ。Cookie は staff_session_id" do
    post staff_session_path, params: { staff_id: @staff.id }

    assert_redirected_to admin_root_url
    assert cookies[:staff_session_id].present?
    assert_nil cookies[:customer_session_id]
  end

  test "ログインしていなければ行員のログイン画面へ。ログイン後は元のページへ戻る" do
    get admin_transfers_path
    assert_redirected_to new_staff_session_path

    post staff_session_path, params: { staff_id: @staff.id }
    assert_redirected_to admin_transfers_url
  end

  test "選んだ行員として入る（行員を切り替えられる）" do
    other = create_staff(name: "くろ")
    sign_in_as_staff @staff
    get admin_root_path
    assert_select "header", /たま/

    sign_in_as_staff other
    get admin_root_path
    assert_select "header", /くろ/
  end

  test "行員を選ばない・いない行員では入れない" do
    post staff_session_path, params: { staff_id: "" }
    assert_redirected_to new_staff_session_path
    assert_nil cookies[:staff_session_id]

    post staff_session_path, params: { staff_id: Staff.maximum(:id) + 1 }
    assert_redirected_to new_staff_session_path
    assert_nil cookies[:staff_session_id]
  end

  test "利用者の id を送っても利用者としては入れない（行員のテーブルだけを見る）" do
    customer = create_customer(name: "オルカ")
    Staff.where(id: customer.id).delete_all

    post staff_session_path, params: { staff_id: customer.id }

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
