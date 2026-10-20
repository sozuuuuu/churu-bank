# 購入者（口座）を選ぶ。認証ができたら要らなくなる
module Shop
  class BuyersController < ApplicationController
    def update
      session[:shop_buyer] = buyers.find_by(number: params[:account_number])&.number
      redirect_back_or_to shop_root_path, status: :see_other
    end
  end
end
