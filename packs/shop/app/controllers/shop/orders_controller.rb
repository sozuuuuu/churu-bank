# 注文。商品一覧ページの Turbo Frame "checkout" の中で動く:
#   create + preview=1（ドライランの確認。ここで注文IDを決める）→ create（受付して注文ページへ）
# 支払いの入金と在庫の引き当て（足りなければ返金）は、受付後にジョブが非同期で行う。
module Shop
  class OrdersController < ApplicationController
    UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    def index
      @orders = ShopOrder.recent.includes(:lines).limit(100)
      @orders = @orders.where(buyer_account: current_buyer.number) if current_buyer
    end

    def show
      @order = ShopOrder.find_by!(order_id: params[:order_id])
      @events = Rails.configuration.event_store.read.stream("Order$#{@order.order_id}").to_a
    end

    def create
      @items = items
      @order_id = params[:order_id].to_s.match?(UUID) ? params[:order_id] : SecureRandom.uuid
      @outcome = store.place_order(order_id: @order_id, buyer_account: current_buyer&.number, items: @items,
                                   dry_run: params[:preview].present?)
      return render :confirm if @outcome.dry_run?

      session.delete(:shop_cart)
      flash_type = @outcome.status == :payment_failed ? :alert : :notice
      redirect_to shop_order_path(@outcome.order_id), flash_type => "注文を受け付けました", status: :see_other
    rescue Shop::AlreadyPlaced
      redirect_to shop_order_path(@order_id), notice: "この注文はもう受け付けています", status: :see_other
    rescue Shop::Error, Banking::Error, ArgumentError => e
      return redirect_to shop_root_path, alert: e.message, status: :see_other unless params[:preview].present?

      @error = e.message
      render :confirm, status: :unprocessable_entity
    end

    private

    # 確認画面からはそのときの中身（hidden）、カートからはセッションの中身
    def items
      source = params[:items].present? ? params.expect(items: ShopProduct.pluck(:sku)).to_h : cart
      source.to_h { |sku, quantity| [ sku.to_s, Integer(quantity.to_s, 10, exception: false) ] }
    end
  end
end
