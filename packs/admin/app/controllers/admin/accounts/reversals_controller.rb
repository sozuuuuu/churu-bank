# 入出金の取消（逆仕訳）の申請。通帳の行の「取消」から、Turbo Frame "reversal" の中で動く:
#   new（理由の入力）→ create + preview=1（ドライランの確認画面）→ create（申請して口座ページへ）
# 取消は二人承認（TODO の Q2）: ここでは申請するだけで、別の行員が承認待ち（/admin/approvals）で承認すると実行される
module Admin
  module Accounts
    class ReversalsController < ApplicationController
      before_action :set_entry

      def new
        @reason = params[:reason].to_s
      end

      def create
        @reason = params[:reason].to_s
        @outcome = desk.request_reversal(@account.number, @entry.event_id, reason: @reason,
                                         dry_run: params[:preview].present?).outcome

        if params[:preview].present?
          render :confirm
        else
          redirect_to admin_account_path(@account), status: :see_other,
                                                    notice: "#{@entry.kind_label}の取消を申請しました。別の行員が承認すると実行されます"
        end
      rescue Banking::Error, ArgumentError => e
        @error = e.message
        render :new, status: :unprocessable_entity
      end

      private

      def set_entry
        @account = Account.find_by!(number: params[:account_number])
        @entry = @account.ledger_entries.find_by!(event_id: params[:event_id])
      end
    end
  end
end
