# 入出金。フォームは Turbo Frame "transaction" の中で動く:
#   new（入力）→ create + preview=1（ドライランの確認画面）→ create（確定して口座ページへ）
module Admin
  module Accounts
    class TransactionsController < ApplicationController
      KINDS = %w[deposit withdrawal].freeze

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
          redirect_to admin_account_path(@account), notice: "#{kind_label}しました",
                      status: :see_other
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
        kind = params[:kind].presence_in(KINDS) || "deposit"
        {
          kind:,
          amount: params[:amount].to_s,
          memo: params[:memo].presence,
          value_date: params[:value_date].presence
        }
      end
      helper_method :kind_label

      def kind_label = @form[:kind] == "deposit" ? "入金" : "出金"

      def perform(dry_run:)
        amount = Integer(@form[:amount], 10, exception: false)
        raise ArgumentError, "金額は1以上の整数で入れてください" unless amount
        value_date = @form[:value_date] && Date.parse(@form[:value_date])
        args = { memo: @form[:memo], value_date:, dry_run: }

        if @form[:kind] == "deposit"
          bank.deposit(@account.number, amount, **args)
        else
          bank.withdraw(@account.number, amount, **args)
        end
      rescue Date::Error
        raise ArgumentError, "起算日の形式が正しくありません"
      end
    end
  end
end
