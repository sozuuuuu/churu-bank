# 注文ページ（行員用）。全員分の注文を見られる（商品と在庫の管理の「最近の注文」から辿る）
module ShopAdmin
  class OrdersController < ApplicationController
    def show
      @order = ShopOrder.find_by!(order_id: params[:order_id])
      @events = Rails.configuration.event_store.read.stream("Order$#{@order.order_id}").to_a
    end
  end
end
