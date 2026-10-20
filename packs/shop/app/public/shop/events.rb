# ちゅ〜る商店で起きる出来事。金額はすべて整数（単位: ちゅ〜る）。
module Shop
  module Events
    # ---- 商店そのもの（ストリーム Shop$main） ----

    # 商店が銀行に自分の口座を開いた。data: account_number
    class ShopOpened < RubyEventStore::Event; end

    # ---- 商品と在庫（ストリーム Product$<sku>） ----

    # data: sku, name, emoji, price
    class ProductListed < RubyEventStore::Event; end

    # data: sku, price
    class ProductPriceChanged < RubyEventStore::Event; end

    # 入荷。data: sku, quantity
    class StockAdded < RubyEventStore::Event; end

    # 支払い済みの注文に在庫を引き当てた（出荷）。data: sku, order_id, quantity
    class StockAllocated < RubyEventStore::Event; end

    # ---- 注文（ストリーム Order$<注文ID>） ----

    # data: order_id, buyer_account, lines（[{ sku, name, unit_price, quantity }]）, total
    class OrderPlaced < RubyEventStore::Event; end

    # 銀行に支払いの振込（購入者 → 商店）を頼んだ。data: order_id, transfer_id
    class OrderPaymentRequested < RubyEventStore::Event; end

    # 支払いの振込が完了した。data: order_id, transfer_id
    class OrderPaid < RubyEventStore::Event; end

    # 支払えなかった（残高不足・振込の組戻しなど）。data: order_id, reason
    class OrderPaymentFailed < RubyEventStore::Event; end

    # 在庫を引き当てて完了。data: order_id
    class OrderFulfilled < RubyEventStore::Event; end

    # 支払い後に在庫が足りず、キャンセルした（このあと返金）。data: order_id, reason
    class OrderCancelled < RubyEventStore::Event; end

    # 返金の振込（商店 → 購入者）を頼んだ。data: order_id, transfer_id
    class OrderRefundRequested < RubyEventStore::Event; end

    # 返金の振込が完了した。data: order_id, transfer_id
    class OrderRefunded < RubyEventStore::Event; end

    # 返金できなかった（人の手で対応が必要）。data: order_id, reason
    class OrderRefundFailed < RubyEventStore::Event; end

    PRODUCT = [ ProductListed, ProductPriceChanged, StockAdded, StockAllocated ].freeze
    ORDER = [
      OrderPlaced, OrderPaymentRequested, OrderPaid, OrderPaymentFailed, OrderFulfilled,
      OrderCancelled, OrderRefundRequested, OrderRefunded, OrderRefundFailed
    ].freeze
    ALL = [ ShopOpened, *PRODUCT, *ORDER ].freeze
  end
end
