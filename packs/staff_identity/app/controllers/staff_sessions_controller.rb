# 行員のログイン（new / create）とログアウト（destroy）。/admin/session
class StaffSessionsController < ApplicationController
  include StaffAuthentication

  allow_unauthenticated_staff_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_staff_session_path, alert: "しばらくしてからもう一度お試しください" }

  layout "application" # packs/ui の外枠（管理画面と同じ見た目）

  def new
  end

  def create
    if staff = Staff.authenticate_by(params.permit(:email_address, :password))
      start_new_staff_session_for staff
      redirect_to after_staff_authentication_url
    else
      redirect_to new_staff_session_path, alert: "メールアドレスかパスワードが違います"
    end
  end

  def destroy
    terminate_staff_session
    redirect_to new_staff_session_path, status: :see_other
  end
end
