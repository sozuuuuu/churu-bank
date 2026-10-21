# 申請の却下（理由つき）。承認待ちの「却下する」から、Turbo Frame "approval" の中で動く:
#   new（理由の入力）→ create + preview=1（確認画面）→ create（却下して承認待ちへ）。銀行は何も変わらない
module Admin
  module Approvals
    class RejectionsController < ApplicationController
      before_action :set_request

      def new
        @reason = params[:reason].to_s
      end

      def create
        @reason = params[:reason].to_s
        desk.reject(@request.approval_id, reason: @reason, dry_run: params[:preview].present?)

        if params[:preview].present?
          render :confirm
        else
          redirect_to admin_approvals_path, notice: "申請を却下しました", status: :see_other
        end
      rescue Banking::Error, ArgumentError => e
        @error = e.message
        @request.reload
        render :new, status: :unprocessable_entity
      end

      private

      def set_request
        @request = ApprovalRequest.find_by!(approval_id: params[:approval_id])
      end
    end
  end
end
