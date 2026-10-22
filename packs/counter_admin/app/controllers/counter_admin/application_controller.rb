# 窓口の列とチャット（行員、/admin/counter/queue）の土台。行員としてログインしていなければ、行員のログイン画面へ（packs/staff_identity）
module CounterAdmin
  class ApplicationController < ::ApplicationController
    include StaffAuthentication
    helper Ui::FormatHelper

    layout "counter_admin"

    rescue_from Counter::Desk::Error do |error|
      redirect_back_or_to counter_admin_queue_path, alert: error.message
    end
  end
end
