require "test_helper"

# Action Cable の接続: 行員か利用者としてログインしている人だけ。どちらでつないだかを接続ごとに持つ
# （署名が Cookie の名前ごとに違うことは test/integration/staff_customer_separation_test.rb で見る）
class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "ログインしていなければ接続できない" do
    assert_reject_connection { connect }
  end

  test "行員の Cookie なら行員としてつながる" do
    staff = create_staff
    cookies.signed[:staff_session_id] = staff.sessions.create!.id

    connect

    assert_equal staff, connection.current_staff
    assert_nil connection.current_customer
  end

  test "利用者の Cookie なら利用者としてつながる" do
    customer = create_customer(name: "オルカ")
    cookies.signed[:customer_session_id] = create_customer_session_id(customer)

    connect

    assert_equal customer, connection.current_customer
    assert_nil connection.current_staff
  end

  test "消えたセッションの Cookie では接続できない" do
    cookies.signed[:staff_session_id] = 0
    cookies.signed[:customer_session_id] = 0

    assert_reject_connection { connect }
  end
end
