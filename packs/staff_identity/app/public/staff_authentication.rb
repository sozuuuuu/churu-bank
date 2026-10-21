# 行員のログイン必須にする concern（Rails 8 の generate authentication がもと）。
# 行員の画面のパックのベースコントローラで include する。ログインしていなければ行員のログイン画面（/admin/session/new）へ。
# 見るのは行員の Cookie（staff_session_id）だけなので、利用者としてログインしていても行員の画面には入れない
module StaffAuthentication
  extend ActiveSupport::Concern

  COOKIE = :staff_session_id

  included do
    before_action :require_staff_authentication
    helper_method :current_staff
    helper StaffHelper
  end

  class_methods do
    def allow_unauthenticated_staff_access(**options)
      skip_before_action :require_staff_authentication, **options
    end
  end

  # Cookie の行員（いなければ nil）。コントローラを通らないところ（Action Cable の接続・ルーティングの制約）で使う。
  # 署名つき Cookie は Cookie の名前ごとに署名が違う（Rails の Cookie のメタデータ）ので、利用者の Cookie の値を
  # staff_session_id に入れても通らない
  def self.staff_from(cookie_jar)
    id = cookie_jar.signed[COOKIE]
    StaffSession.find_by(id:)&.staff if id
  end

  # ルーティングの制約に使う: constraints(StaffAuthentication::Constraint) { ... }
  # コントローラを通らない Rack アプリ（RES Browser）を行員だけに見せるため。行員でなければ 404
  module Constraint
    def self.matches?(request) = StaffAuthentication.staff_from(request.cookie_jar).present?
  end

  private
    def current_staff = StaffCurrent.staff

    def require_staff_authentication
      resume_staff_session || request_staff_authentication
    end

    def resume_staff_session
      StaffCurrent.session ||= find_staff_session_by_cookie
    end

    def find_staff_session_by_cookie
      StaffSession.find_by(id: cookies.signed[COOKIE]) if cookies.signed[COOKIE]
    end

    def request_staff_authentication
      session[:staff_return_to] = request.url
      redirect_to new_staff_session_path
    end

    def after_staff_authentication_url
      session.delete(:staff_return_to) || admin_root_url
    end

    def start_new_staff_session_for(staff)
      staff.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |staff_session|
        StaffCurrent.session = staff_session
        cookies.signed.permanent[COOKIE] = { value: staff_session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_staff_session
      StaffCurrent.session&.destroy
      cookies.delete(COOKIE)
    end
end
