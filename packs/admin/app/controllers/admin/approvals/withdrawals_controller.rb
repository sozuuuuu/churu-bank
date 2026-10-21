# 申請の取り下げ（申請した本人だけ）。承認待ちの「取り下げる」（POST）
module Admin
  module Approvals
    class WithdrawalsController < ApplicationController
      def create
        desk.withdraw(params[:approval_id])
        redirect_to admin_approvals_path, notice: "申請を取り下げました", status: :see_other
      rescue Banking::Error => e
        redirect_to admin_approvals_path, alert: e.message, status: :see_other
      end
    end
  end
end
