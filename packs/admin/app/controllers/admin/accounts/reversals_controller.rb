# 入出金の取消（逆仕訳）。通帳の行の「取消」から、Turbo Frame "reversal" の中で動く:
#   new（理由の入力）→ create + preview=1（ドライランの確認画面）→ create（確定して口座ページへ）
module Admin
  module Accounts
    class ReversalsController < ApplicationController
      before_action :set_entry

      def new
        @reason = params[:reason].to_s
      end

      def create
        @reason = params[:reason].to_s
        @outcome = bank.reverse(@account.number, @entry.event_id, reason: @reason.strip,
                                                                  dry_run: params[:preview].present?)

        if @outcome.dry_run?
          render :confirm
        else
          redirect_to admin_account_path(@account), notice: "#{@entry.kind_label}を取り消しました",
                                                    status: :see_other
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
