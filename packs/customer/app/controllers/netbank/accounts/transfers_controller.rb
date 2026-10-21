# 自分の口座からの振込。Turbo Frame "transfer" の中で動く:
#   new（入力）→ create + preview=1（ドライランの確認画面）→ create（受付して口座ページへ）
module Netbank
  module Accounts
    class TransfersController < ApplicationController
      before_action :set_account

      def new
        @form = form_params
      end

      def create
        @form = form_params
        @outcome = perform(dry_run: params[:preview].present?)

        if @outcome.dry_run?
          render :confirm
        else
          redirect_to account_path(@account), notice: "振込を受け付けました", status: :see_other
        end
      rescue Banking::Error, ArgumentError => e
        @error = e.message
        render :new, status: :unprocessable_entity
      end

      private

      def set_account
        @account = find_my_account(params[:account_number])
        @destinations = Account.where.not(number: @account.number).where.not(status: "closed").order(:number)
      end

      def form_params
        { to: params[:to].presence, amount: params[:amount].to_s, memo: params[:memo].presence }
      end

      def perform(dry_run:)
        raise ArgumentError, "この口座は#{@account.status_label}なので振り込めません" unless @account.active?
        amount = Integer(@form[:amount], 10, exception: false)
        raise ArgumentError, "金額は1以上の整数で入れてください" unless amount
        raise ArgumentError, "振込先を選んでください" unless @form[:to]

        bank.transfer(@account.number, @form[:to], amount, memo: @form[:memo], dry_run:)
      end
    end
  end
end
