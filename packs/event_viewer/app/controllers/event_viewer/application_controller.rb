# イベントビューア（/admin/events）の土台。行員としてログインしていなければ、行員のログイン画面へ（packs/staff_identity）。
# 読むだけなので Banking::Bank などの入口は使わない
module EventViewer
  class ApplicationController < ::ApplicationController
    include StaffAuthentication
    helper Ui::FormatHelper
    helper Ui::ThemeHelper # 線画のアイコン（icon）
    helper EventViewer::EventsHelper

    layout "event_viewer"

    private

    def names = @names ||= Names.new
    helper_method :names
  end
end
