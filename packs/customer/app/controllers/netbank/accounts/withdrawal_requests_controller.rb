# 自分の口座からの出金依頼（窓口取引、TODO の Q1）。出金は利用者の依頼を行員が処理したときだけ。
# フォームは Turbo Frame "withdrawal_request" の中で動く:
#   new（入力）→ create + preview=1（ドライランの確認画面）→ create（依頼を出して口座ページへ）
# 行員が処理する前なら destroy で取り消せる（他人の口座の依頼は 404）
module Netbank
  module Accounts
    class WithdrawalRequestsController < ApplicationController
      before_action :set_account

      def new
        @form = form_params
      end

      def create
        @form = form_params
        amount = Integer(@form[:amount], 10, exception: false)
        raise ArgumentError, "金額は1以上の整数で入れてください" unless amount

        @outcome = bank.request_withdrawal(@account.number, amount, memo: @form[:memo], dry_run: params[:preview].present?)
        if @outcome.dry_run?
          render :confirm
        else
          redirect_to account_path(@account), status: :see_other,
                                              notice: "出金を依頼しました。銀行の窓口で処理されると口座から出金されます"
        end
      rescue Banking::Error, ArgumentError => e
        @error = e.message
        render :new, status: :unprocessable_entity
      end

      def destroy
        request = WithdrawalRequest.where(account_number: @account.number).find_by!(request_id: params[:id])
        bank.cancel_withdrawal(request.request_id, from: @account.number)
        redirect_to account_path(@account), notice: "出金依頼を取り消しました", status: :see_other
      rescue Banking::Error => e
        redirect_to account_path(@account), alert: e.message, status: :see_other
      end

      private

      def set_account
        @account = find_my_account(params[:account_number])
      end

      def form_params = { amount: params[:amount].to_s, memo: params[:memo].presence }
    end
  end
end
