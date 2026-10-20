# 商品一覧（カートと注文の確認もこのページ）
module Shop
  class ProductsController < ApplicationController
    def index
      @products = ShopProduct.order(:id)
      @cart_lines = ShopProduct.where(sku: cart.keys).index_by(&:sku).values_at(*cart.keys).compact
                               .map { [ it, cart.fetch(it.sku) ] }
    end
  end
end
