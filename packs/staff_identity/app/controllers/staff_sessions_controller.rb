# 行員のログイン（new / create）とログアウト（destroy）。/admin/session
# 学習用なのでパスワードは使わない: ドロップダウンで行員を選ぶだけで、その行員のセッション（staff_session_id）を作る。
# 利用者のセッション（customer_session_id）とは別のまま
class StaffSessionsController < ApplicationController
  include StaffAuthentication

  allow_unauthenticated_staff_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_staff_session_path, alert: "しばらくしてからもう一度お試しください" }

  layout "application" # packs/ui の外枠（管理画面と同じ見た目）

  def new
    @staffs = Staff.order(:id)
  end

  def create
    if staff = Staff.find_by(id: params[:staff_id])
      start_new_staff_session_for staff
      redirect_to after_staff_authentication_url
    else
      redirect_to new_staff_session_path, alert: "行員を選んでください"
    end
  end

  def destroy
    terminate_staff_session
    redirect_to new_staff_session_path, status: :see_other
  end
end
