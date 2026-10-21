# 商品と在庫の管理（登録・値段の変更）。入荷は RestocksController
module ShopAdmin
  class ProductsController < ApplicationController
    def index
      @products = ShopProduct.order(:id)
      @orders = ShopOrder.recent.includes(:lines).limit(50)
      @shop_account = Account.find_by(number: store.account_number)
    end

    def create
      store.register_product(sku: params[:sku].to_s.strip, name: params[:name].to_s.strip,
                             emoji: params[:emoji].to_s.strip, price: integer(params[:price]))
      redirect_to shop_admin_products_path, notice: "商品を登録しました", status: :see_other
    rescue Shop::Error, ArgumentError => e
      redirect_to shop_admin_products_path, alert: e.message, status: :see_other
    end

    # 値段の変更
    def update
      store.change_price(params[:sku], integer(params[:price]))
      redirect_to shop_admin_products_path, notice: "値段を変えました", status: :see_other
    rescue Shop::Error, ArgumentError => e
      redirect_to shop_admin_products_path, alert: e.message, status: :see_other
    end

    private

    def integer(value) = Integer(value.to_s, 10, exception: false)
  end
end
