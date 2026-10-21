# 利息の手動実行（全口座）。ふだんは Interest::PayJob が毎日前日分を払うので、止まっていた日の分などに使う。
# Turbo Frame "interest" の中で動く:
#   show（利率と日付の入力）→ create + preview=1（口座ごとの支払額の確認）→ create（確定してこの画面へ）
# 同じ日の利息は1回だけ。支払い済みの日は確認画面でそう表示し、確定しても何も起きない
module Admin
  class InterestsController < ApplicationController
    include InterestPayment

    def show
      @date = parse_interest_date || Date.yesterday
    end

    def create
      @date = interest_date!
      if params[:preview].present?
        @rows = Account.order(:number).map { interest_row(it, @date) }
        render :confirm
      else
        redirect_to admin_interest_path(date: @date), status: :see_other,
                                                      **interest_notice(bank.pay_interest(date: @date), @date)
      end
    rescue Banking::Error, ArgumentError => e
      @error = e.message
      @date ||= parse_interest_date || Date.yesterday
      render :show, status: :unprocessable_entity
    end
  end
end
