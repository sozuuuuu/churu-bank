# 自分の口座からの振込。Turbo Frame "transfer" の中で動く:
#   new（入力）→ create + preview=1（ドライランの確認画面）→ create（受付して口座ページへ）
# 実行日（execute_on）を入れると予約振込（引き落としは実行日）。空ならすぐ振り込む
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
          redirect_to account_path(@account), notice: done_message, status: :see_other
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
        { to: params[:to].presence, amount: params[:amount].to_s, memo: params[:memo].presence,
          execute_on: params[:execute_on].presence }
      end

      def perform(dry_run:)
        raise ArgumentError, "この口座は#{@account.status_label}なので振り込めません" unless @account.active?
        amount = Integer(@form[:amount], 10, exception: false)
        raise ArgumentError, "金額は1以上の整数で入れてください" unless amount
        raise ArgumentError, "振込先を選んでください" unless @form[:to]

        bank.transfer(@account.number, @form[:to], amount, memo: @form[:memo], execute_on: @form[:execute_on], dry_run:)
      end

      def done_message
        status = Transfer.find_by(transfer_id: @outcome.transfer_id)&.status
        case status
        when "scheduled" then "振込を予約しました（#{Date.iso8601(@form[:execute_on]).strftime('%-m/%-d')} に振り込みます）"
        when "held" then "振込を受け付けました。金額が大きいので、銀行の確認が終わるまで保留中です"
        else "振込を受け付けました"
        end
      end
    end
  end
end
