# 出金依頼の処理（出金する）。窓口の「出金する」から、Turbo Frame "counter" の中で動く:
#   new（ドライランの確認画面）→ create（出金して窓口へ）
# 二重に処理しようとしたら（ほかの行員が先に処理した・利用者が取り消した）エラーを出す
module Admin
  module WithdrawalRequests
    class ProcessingsController < ApplicationController
      before_action :set_request

      def new
        @outcome = bank.process_withdrawal(@request.request_id, dry_run: true)
      rescue Banking::Error => e
        @error = e.message
      end

      def create
        bank.process_withdrawal(@request.request_id)
        redirect_to admin_withdrawal_requests_path,
                    notice: "#{@request.account.holder_name} さんに #{@request.amount} ちゅ〜る出金しました", status: :see_other
      rescue Banking::Error => e
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
