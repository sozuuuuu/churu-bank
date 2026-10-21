# 購入者（自分の口座のどれで払うか）を選ぶ。自分の口座以外は選べない（無視する）
module Shop
  class BuyersController < ApplicationController
    def update
      if (account = buyers.find_by(number: params[:account_number]))
        session[:shop_buyer] = account.number
      else
        flash[:alert] = "その口座では買えません"
      end
      redirect_back_or_to shop_root_path, status: :see_other
    end
  end
end
