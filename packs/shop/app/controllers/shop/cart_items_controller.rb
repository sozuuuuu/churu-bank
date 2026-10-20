# カートに入れる・出す（セッションだけ。イベントにはしない）
module Shop
  class CartItemsController < ApplicationController
    def create
      product = ShopProduct.find_by!(sku: params[:sku])
      quantity = Integer(params[:quantity].to_s, 10, exception: false)
      if quantity&.positive?
        cart[product.sku] = cart.fetch(product.sku, 0) + quantity
      else
        flash[:alert] = "数は1以上の整数で入れてください"
      end
      redirect_to shop_root_path, status: :see_other
    end

    def destroy
      cart.delete(params[:sku])
      redirect_to shop_root_path, status: :see_other
    end
  end
end
