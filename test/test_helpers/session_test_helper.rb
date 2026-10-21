# ログインまわりのテスト用ヘルパー。行員（Staff）と利用者（Customer）は別のアカウント・別のログイン。
# ログインは本物のログイン画面に POST する（Cookie も本物と同じ名前・署名になる）
module SessionTestHelper
  TEST_PASSWORD = "test-password"

  def create_staff(name: "行員", email_address: "#{SecureRandom.hex(4)}@staff.example.com")
    Staff.create!(name:, email_address:, password: TEST_PASSWORD)
  end

  def create_customer(name:, email_address: "#{SecureRandom.hex(4)}@example.com")
    Customer.create!(name:, email_address:, password: TEST_PASSWORD)
  end

  # 利用者のセッションを直接作って id を返す（Action Cable の接続のテスト用。customer_sessions は customer_identity の
  # 非公開のテーブルなので、テストの中だけの AR で書く。行員は Staff#sessions が公開なのでそちらを使う）
  def create_customer_session_id(customer) = TestCustomerSession.create!(customer_id: customer.id).id

  class TestCustomerSession < ApplicationRecord
    self.table_name = "customer_sessions"
  end

  def sign_in_as_staff(staff)
    post staff_session_path, params: { email_address: staff.email_address, password: TEST_PASSWORD }
    raise "行員としてログインできませんでした" if cookies[:staff_session_id].blank?
  end

  def sign_in_as_customer(customer)
    post customer_session_path, params: { customer_id: customer.id } # 利用者のログインはドロップダウンで選ぶだけ（パスワードなし）
    raise "利用者としてログインできませんでした" if cookies[:customer_session_id].blank?
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
ActiveSupport.on_load(:active_support_test_case) do
  include SessionTestHelper
end
