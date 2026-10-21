# 出金依頼を断る。窓口の「断る」から、Turbo Frame "counter" の中で動く:
#   new（理由の入力）→ create + preview=1（確認画面）→ create（断って窓口へ）。お金は動かない
module Admin
  module WithdrawalRequests
    class RejectionsController < ApplicationController
      before_action :set_request

      def new
        @reason = params[:reason].to_s
      end

      def create
        @reason = params[:reason].to_s
        @outcome = bank.reject_withdrawal(@request.request_id, reason: @reason, dry_run: params[:preview].present?)

        if @outcome.dry_run?
          render :confirm
        else
          redirect_to admin_withdrawal_requests_path, notice: "出金依頼を断りました", status: :see_other
        end
      rescue Banking::Error, ArgumentError => e
        @error = e.message
        @request.reload
        render :new, status: :unprocessable_entity
      end

      private

      def set_request
        @request = WithdrawalRequest.includes(:account).find_by!(request_id: params[:withdrawal_request_id])
      end
    end
  end
end
