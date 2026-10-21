# 入荷（在庫を増やす）
module Shop
  module Admin
    class RestocksController < Admin::ApplicationController
      def create
        store.restock(params[:product_sku], Integer(params[:quantity].to_s, 10, exception: false))
        redirect_to shop_admin_products_path, notice: "入荷しました", status: :see_other
      rescue Shop::Error, ArgumentError => e
        redirect_to shop_admin_products_path, alert: e.message, status: :see_other
      end
    end
  end
end
