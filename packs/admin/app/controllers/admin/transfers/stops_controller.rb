# 実行前（予約中・保留中）の振込の差し止め。振込一覧の「差し止める」から、Turbo Frame "hold" の中で動く:
#   new（理由の入力）→ create + preview=1（ドライランの確認画面）→ create（差し止めて振込一覧へ）
# 引き落とし済み（保留中）なら振込元へ払い戻す
module Admin
  module Transfers
    class StopsController < ApplicationController
      before_action :set_transfer

      def new
        @reason = params[:reason].to_s
      end

      def create
        @reason = params[:reason].to_s
        @outcome = bank.stop_transfer(@transfer.transfer_id, reason: @reason.strip, dry_run: params[:preview].present?)

        if @outcome.dry_run?
          render :confirm
        else
          redirect_to admin_transfers_path, notice: "振込を差し止めました", status: :see_other
        end
      rescue Banking::Error, ArgumentError => e
        @error = e.message
        @transfer.reload
        render :new, status: :unprocessable_entity
      end

      private

      def set_transfer
        @transfer = Transfer.includes(:source, :destination).find_by!(transfer_id: params[:transfer_id])
      end
    end
  end
end
