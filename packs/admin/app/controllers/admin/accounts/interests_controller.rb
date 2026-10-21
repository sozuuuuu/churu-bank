# 1口座だけ利息を払う。口座ページの Turbo Frame "interest" の中で動く:
#   new（日付の入力）→ create + preview=1（支払額の確認）→ create（確定して口座ページへ）
module Admin
  module Accounts
    class InterestsController < ApplicationController
      include InterestPayment

      before_action :set_account

      def new
        @date = parse_interest_date || Date.yesterday
      end

      def create
        @date = interest_date!
        if params[:preview].present?
          @row = interest_row(@account, @date)
          render :confirm
        else
          outcomes = [ bank.pay_interest_to(@account.number, date: @date) ].compact
          redirect_to admin_account_path(@account), status: :see_other, **interest_notice(outcomes, @date)
        end
      rescue Banking::Error, ArgumentError => e
        @error = e.message
        @date ||= parse_interest_date || Date.yesterday
        render :new, status: :unprocessable_entity
      end

      private

      def set_account
        @account = Account.find_by!(number: params[:account_number])
      end
    end
  end
end
