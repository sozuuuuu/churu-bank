# 高額で保留中の振込を通す。振込一覧の「通す」から、Turbo Frame "hold" の中で動く:
#   new（振込の内容）→ create + preview=1（ドライランの確認画面）→ create（通して振込一覧へ）
# 通したあとは、ふつうの振込と同じく Transfers::SettleJob が入金する
module Admin
  module Transfers
    class ReleasesController < ApplicationController
      before_action :set_transfer

      def new
      end

      def create
        @outcome = bank.release_transfer(@transfer.transfer_id, dry_run: params[:preview].present?)

        if @outcome.dry_run?
          render :confirm
        else
          redirect_to admin_transfers_path, notice: "保留中の振込を通しました", status: :see_other
        end
      rescue Banking::Error => e
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
