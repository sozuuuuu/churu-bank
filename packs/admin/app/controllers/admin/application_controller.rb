# 管理画面（行員用）のベース。行員としてログインしていなければ、行員のログイン画面（/admin/session/new）へ。
# 利用者としてログインしていても入れない（Cookie もセッションも別。packs/staff_identity）
module Admin
  class ApplicationController < ::ApplicationController
    include StaffAuthentication
    helper Ui::FormatHelper
    helper Admin::ActorsHelper

    layout "admin"

    private

    # 誰の操作かをイベントの metadata（actor）に残す（staff:<id>）
    def bank = @bank ||= Banking::Bank.new(actor: current_staff.actor)

    # 取消・組戻し・凍結の解除は、ここから申請して別の行員が承認する（二人承認、packs/approvals）
    def desk = @desk ||= ::Approvals::Desk.new(actor: current_staff.actor)
  end
end
