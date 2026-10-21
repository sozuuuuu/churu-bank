# Action Cable（Turbo のライブ更新）の接続。行員か利用者としてログインしている人だけ。
# 接続ごとに「行員としてつないだか（current_staff）」「利用者としてつないだか（current_customer）」を持ち、
# 購読できるチャンネルが分かれる: 行員は StaffStreamsChannel、利用者は CustomerStreamsChannel だけ。
# 素の Turbo::StreamsChannel は購読させない（config/initializers/turbo_streams.rb）
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_staff, :current_customer

    def connect
      self.current_staff = StaffAuthentication.staff_from(cookies)
      self.current_customer = CustomerAuthentication.customer_from(cookies)
      reject_unauthorized_connection unless current_staff || current_customer
    end
  end
end
