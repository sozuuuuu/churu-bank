# 実行前（予約中・保留中）の自分の振込の取消。口座ページの「取り消す」から、Turbo Frame "cancellation" の中で動く:
#   new（振込の内容）→ create + preview=1（ドライランの確認画面）→ create（取り消して口座ページへ）
# 自分の口座からの振込でなければ 404。実行が始まっていたら（ちょうど実行日になった等）エラーを出す
module Customer
  module Accounts
    class CancellationsController < ApplicationController
      before_action :set_transfer

      def new
      end

      def create
        @outcome = bank.cancel_transfer(@transfer.transfer_id, from: @account.number, dry_run: params[:preview].present?)

        if @outcome.dry_run?
          render :confirm
        else
          redirect_to account_path(@account), notice: "振込を取り消しました", status: :see_other
        end
      rescue Banking::Error => e
        @error = e.message
        @transfer.reload
        render :new, status: :unprocessable_entity
      end

      private

      def set_transfer
        @account = find_my_account(params[:account_number])
        @transfer = Transfer.includes(:destination).where(from_account: @account.number)
                            .find_by!(transfer_id: params[:transfer_id])
      end
    end
  end
end
