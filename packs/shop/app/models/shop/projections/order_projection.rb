# イベント → 読み取りモデル（shop_orders / shop_order_lines）。publish と同じトランザクションで同期的に呼ばれる
module Shop
  module Projections
    class OrderProjection
      STATUSES = {
        Events::OrderPaymentRequested => "payment_pending",
        Events::OrderPaid => "paid",
        Events::OrderPaymentFailed => "payment_failed",
        Events::OrderFulfilled => "fulfilled",
        Events::OrderCancelled => "cancelled",
        Events::OrderRefundRequested => "refunding",
        Events::OrderRefunded => "refunded",
        Events::OrderRefundFailed => "refund_failed"
      }.freeze

      def call(event)
        data = event.data
        return place(event) if event.is_a?(Events::OrderPlaced)

        order = ShopOrder.find_by!(order_id: data.fetch(:order_id))
        attributes = { status: STATUSES.fetch(event.class), updated_at: event.timestamp }
        case event
        when Events::OrderPaymentRequested then attributes[:payment_transfer_id] = data.fetch(:transfer_id)
        when Events::OrderRefundRequested then attributes[:refund_transfer_id] = data.fetch(:transfer_id)
        when Events::OrderPaymentFailed, Events::OrderCancelled, Events::OrderRefundFailed
          attributes[:failure_reason] = data[:reason]
        end
        order.update!(attributes)
      end

      private

      def place(event)
        data = event.data
        order = ShopOrder.create!(
          order_id: data.fetch(:order_id), buyer_account: data.fetch(:buyer_account), total: data.fetch(:total),
          status: "placed", placed_at: event.timestamp, actor: event.metadata[:actor]
        )
        data.fetch(:lines).each do |line|
          line = line.to_h.symbolize_keys
          order.lines.create!(line.slice(:sku, :name, :unit_price, :quantity))
        end
      end
    end
  end
end
