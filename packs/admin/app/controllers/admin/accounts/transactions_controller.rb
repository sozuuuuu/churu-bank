# 入金（現金の持ち込み）。行員だけができる。フォームは Turbo Frame "transaction" の中で動く:
#   new（入力）→ create + preview=1（ドライランの確認画面）→ create（確定して口座ページへ）
# 出金はここではできない。利用者の出金依頼を窓口（Admin::WithdrawalRequestsController）で処理する（TODO の Q1）
module Admin
  module Accounts
    class TransactionsController < ApplicationController
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
          redirect_to admin_account_path(@account), notice: "入金しました", status: :see_other
        end
      rescue Banking::Error, ArgumentError => e
        @error = e.message
        render :new, status: :unprocessable_entity
      end

      private

      def set_account
        @account = Account.find_by!(number: params[:account_number])
      end

      def form_params
        { amount: params[:amount].to_s, memo: params[:memo].presence, value_date: params[:value_date].presence }
      end

      def perform(dry_run:)
        amount = Integer(@form[:amount], 10, exception: false)
        raise ArgumentError, "金額は1以上の整数で入れてください" unless amount
        value_date = @form[:value_date] && Date.parse(@form[:value_date])

        bank.deposit(@account.number, amount, memo: @form[:memo], value_date:, dry_run:)
      rescue Date::Error
        raise ArgumentError, "起算日の形式が正しくありません"
      end
    end
  end
end
