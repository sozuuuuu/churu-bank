# 商店の口座を銀行に開く（開いてあれば何もしない）
module Shop
  module Admin
    class OpeningsController < ApplicationController
      def create
        store.open_shop
        redirect_to shop_admin_products_path, notice: "商店の口座を開きました", status: :see_other
      end
    end
  end
end
