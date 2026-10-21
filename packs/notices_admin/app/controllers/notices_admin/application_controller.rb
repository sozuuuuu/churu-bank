# 行員のお知らせの画面（/admin/notices）の土台。行員としてログインしていなければ、行員のログイン画面へ（packs/staff_identity）
module NoticesAdmin
  class ApplicationController < ::ApplicationController
    include StaffAuthentication
    helper Ui::FormatHelper

    layout "notices_admin"

    private

    # だれが出したか（posted_by）は staff:<id>
    def board = @board ||= Notices::Board.new(actor: current_staff.actor)
  end
end
