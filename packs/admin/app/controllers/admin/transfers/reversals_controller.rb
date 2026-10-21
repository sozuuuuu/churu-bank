# 完了した振込の組戻しの申請。振込一覧・口座ページの「組戻し」から、Turbo Frame "reversal" の中で動く:
#   new（理由の入力）→ create + preview=1（ドライランの確認画面）→ create（申請して元の画面へ）
# 組戻しは二人承認（TODO の Q2）: 別の行員が承認待ち（/admin/approvals）で承認すると実行される
# 口座ページから来たときは back_to に口座番号が入っていて、確定後はその口座ページへ戻る
module Admin
  module Transfers
    class ReversalsController < ApplicationController
      before_action :set_transfer

      def new
        @reason = params[:reason].to_s
      end

      def create
        @reason = params[:reason].to_s
        @outcome = desk.request_transfer_reversal(@transfer.transfer_id, reason: @reason,
                                                  dry_run: params[:preview].present?).outcome

        if params[:preview].present?
          @destination_before = bank.load_account(@transfer.to_account).balance
          render :confirm
        else
          redirect_to back_path, notice: "振込の組戻しを申請しました。別の行員が承認すると実行されます", status: :see_other
        end
      rescue Banking::Error, ArgumentError => e
        @error = e.message
        render :new, status: :unprocessable_entity
      end

      private

      def set_transfer
        @transfer = Transfer.includes(:source, :destination).find_by!(transfer_id: params[:transfer_id])
        @back_to = params[:back_to].presence_in([ @transfer.from_account, @transfer.to_account ])
      end

      helper_method :back_path

      def back_path = @back_to ? admin_account_path(@back_to) : admin_transfers_path
    end
  end
end
