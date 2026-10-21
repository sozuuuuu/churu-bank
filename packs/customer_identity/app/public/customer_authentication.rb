# 利用者のログイン必須にする concern（Rails 8 の generate authentication がもと）。
# 利用者の画面のパックのベースコントローラで include する。ログインしていなければ利用者のログイン画面（/session/new）へ。
# 見るのは利用者の Cookie（customer_session_id）だけなので、行員としてログインしていても利用者の画面には入れない
module CustomerAuthentication
  extend ActiveSupport::Concern

  COOKIE = :customer_session_id

  included do
    before_action :require_customer_authentication
    helper_method :current_customer
    helper CustomerHelper
  end

  class_methods do
    def allow_unauthenticated_customer_access(**options)
      skip_before_action :require_customer_authentication, **options
    end
  end

  # Cookie の利用者（いなければ nil）。コントローラを通らないところ（Action Cable の接続）で使う。
  # 署名つき Cookie は Cookie の名前ごとに署名が違うので、行員の Cookie の値を customer_session_id に入れても通らない
  def self.customer_from(cookie_jar)
    id = cookie_jar.signed[COOKIE]
    CustomerSession.find_by(id:)&.customer if id
  end

  private
    def current_customer = CustomerCurrent.customer

    def require_customer_authentication
      resume_customer_session || request_customer_authentication
    end

    def resume_customer_session
      CustomerCurrent.session ||= find_customer_session_by_cookie
    end

    def find_customer_session_by_cookie
      CustomerSession.find_by(id: cookies.signed[COOKIE]) if cookies.signed[COOKIE]
    end

    def request_customer_authentication
      session[:customer_return_to] = request.url
      redirect_to new_customer_session_path
    end

    def after_customer_authentication_url
      session.delete(:customer_return_to) || root_url
    end

    def start_new_customer_session_for(customer)
      CustomerSession.create!(customer:, user_agent: request.user_agent, ip_address: request.remote_ip).tap do |customer_session|
        CustomerCurrent.session = customer_session
        cookies.signed.permanent[COOKIE] = { value: customer_session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_customer_session
      CustomerCurrent.session&.destroy
      cookies.delete(COOKIE)
    end
end
