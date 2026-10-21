# 完了した振込の組戻し。振込一覧・口座ページの「組戻し」から、Turbo Frame "reversal" の中で動く:
#   new（理由の入力）→ create + preview=1（ドライランの確認画面）→ create（確定して元の画面へ）
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
        @outcome = bank.reverse_transfer(@transfer.transfer_id, reason: @reason.strip,
                                                                dry_run: params[:preview].present?)

        if @outcome.dry_run?
          @destination_before = bank.load_account(@transfer.to_account).balance
          render :confirm
        else
          redirect_to back_path, notice: "振込を組戻ししました", status: :see_other
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
