# ログインまわりのテスト用ヘルパー（Rails 8 の generate authentication がもと）
module SessionTestHelper
  TEST_PASSWORD = "test-password"

  def create_user(name:, admin: false, email_address: "#{SecureRandom.hex(4)}@example.com")
    User.create!(name:, admin:, email_address:, password: TEST_PASSWORD)
  end

  def sign_in_as(user)
    Current.session = user.sessions.create!

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:session_id] = Current.session.id
      cookies["session_id"] = cookie_jar[:session_id]
    end
  end

  def sign_out
    Current.session&.destroy!
    cookies.delete("session_id")
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
ActiveSupport.on_load(:active_support_test_case) do
  include SessionTestHelper
end
