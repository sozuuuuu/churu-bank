require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "メールアドレスは前後の空白を取って小文字にする" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "口座をひも付けると account_numbers と owning で引ける" do
    orca = create_user(name: "オルカ")
    other = create_user(name: "ジンジベル")

    orca.grant_account("0000002")
    orca.grant_account("0000001")
    orca.grant_account("0000001") # 2回目は何もしない

    assert_equal %w[0000001 0000002], orca.account_numbers
    assert orca.owns_account?("0000001")
    assert_not other.owns_account?("0000001")
    assert_equal [ orca ], User.owning("0000001").to_a
  end
end
