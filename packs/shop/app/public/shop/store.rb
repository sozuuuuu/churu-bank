# ちゅ〜る商店を操作する唯一の入口。画面・コンソール・（あとで）ほかのパックはすべてここを通す。
#
#   store = Shop::Store.new(actor: "web")
#   store.open_shop                                         # 銀行に商店の口座を開く（1回だけ）
#   store.register_product(sku: "churu", name: "ちゅ〜る", price: 30)
#   store.restock("churu", 10)
#   store.place_order(order_id:, buyer_account: "0000001", items: { "churu" => 2 }, dry_run: true)
#
# 支払いと返金は銀行の振込（Banking::Bank#transfer）。商店は銀行の公開 API しか使わない。
# 決まった加盟店への支払いなので、高額振込の保留の対象外（holdable: false）。
#
#   place_order（同期・1トランザクション）
#     Order$<id>  … OrderPlaced → OrderPaymentRequested（銀行で 購入者 → 商店 の振込を受付）
#           │ 銀行の Transfers::SettleJob が入金して TransferCompleted / TransferFailed
#           ▼
#   Shop::PaymentJob（TransferCompleted / TransferFailed を購読）→ settle_transfer
#     ├ 支払い完了 → 在庫を引き当て → OrderPaid → OrderFulfilled
#     │              在庫が足りない → OrderPaid → OrderCancelled → OrderRefundRequested（商店 → 購入者 の振込）
#     ├ 支払い失敗 → OrderPaymentFailed
#     └ 返金の完了 / 失敗 → OrderRefunded / OrderRefundFailed
#
# 在庫は「支払い前には引き当てない」。注文時は在庫を見て警告するだけで、引き当ては支払いが
# 終わってから。支払い待ちの注文が在庫を抱えたままになる（期限切れの解放が要る）のを避けるかわりに、
# 支払い後に在庫が足りなければ返金する（補償）。
#
# 振込IDと注文の対応は、OrderPaymentRequested / OrderRefundRequested をストリーム
# ShopTransfer$<振込ID> にリンクして持つ（読み取りモデルではなくイベントストアが正）。
module Shop
  class Store
    SHOP_NAME = "ちゅ〜る商店".freeze
    SHOP_STREAM = "Shop$main".freeze

    # ドライランでも本番でも同じ形で返す。payment は銀行の振込の Outcome（支払えなかったときは nil）
    Outcome = Data.define(:order_id, :status, :total, :events, :payment, :warnings, :dry_run) do
      def dry_run? = dry_run
    end

    def initialize(actor:, event_store: Rails.configuration.event_store)
      @actor = actor
      @event_store = event_store
      @repository = AggregateRoot::Repository.new(event_store)
      @bank = Banking::Bank.new(actor:, event_store:)
    end

    # ---- 商店 ----

    # 商店の口座を開く。開いてあれば何もしない
    def open_shop
      return account_number if opened?

      transaction do
        number = @bank.open_account(holder_name: SHOP_NAME).account_number
        @event_store.publish(Events::ShopOpened.new(data: { account_number: number }),
                             stream_name: SHOP_STREAM, expected_version: :none)
        number
      end
    end

    def account_number
      @event_store.read.stream(SHOP_STREAM).of_type(Events::ShopOpened).last&.data&.fetch(:account_number)
    end

    def opened? = account_number.present?

    # ---- 商品と在庫 ----

    def register_product(sku:, name:, price:, emoji: nil, dry_run: false)
      change_product(sku, dry_run:) { it.list(name:, price:, emoji:) }
    end

    def change_price(sku, price, dry_run: false)
      change_product(sku, dry_run:) { it.change_price(price) }
    end

    def restock(sku, quantity, dry_run: false)
      change_product(sku, dry_run:) { it.restock(quantity) }
    end

    # ---- 注文 ----

    # 注文を受け付けて、支払いの振込（購入者 → 商店）を頼む。items は { sku => 数 }。
    # order_id は呼ぶ側が決める（確認画面で発行して、確定のときにも同じものを送る）。
    # 残高不足などで振込を受け付けてもらえなければ、注文は「支払い失敗」で残る。
    # ドライランでは、振込もドライランで確かめる（残高不足なら Banking::InsufficientFunds が上がる）
    def place_order(order_id:, buyer_account:, items:, dry_run: false)
      shop_account = account_number or raise NotOpen, "商店の口座がまだありません"
      order = load_order(order_id)
      warnings = []
      lines = items.map do |sku, quantity|
        product = load_product(sku)
        raise NotFound, "商品 #{sku} はありません" unless product.listed?
        if quantity.is_a?(Integer) && quantity > product.stock
          warnings << "#{product.name} は在庫が #{product.stock} しかないので、支払い後にキャンセル・返金になります"
        end
        Order::Line.new(sku:, name: product.name, unit_price: product.price, quantity:)
      end
      order.place(buyer_account:, lines:)
      memo = "#{SHOP_NAME} 注文 #{order_id.first(8)}"

      if dry_run
        payment = @bank.transfer(buyer_account, shop_account, order.total, memo:, holdable: false, dry_run: true)
        order.request_payment(payment.transfer_id)
        return outcome(order, payment:, warnings:, dry_run: true)
      end

      # 注文と支払いの引き落としを同じ correlation_id にして、RES Browser で1本の流れとして辿れるようにする
      transaction(correlation_id: order_id) do
        payment = pay(order) { @bank.transfer(buyer_account, shop_account, order.total, memo:, holdable: false) }
        order.request_payment(payment.transfer_id) if payment
        events = order.unpublished_events.to_a
        @repository.store(order, Order.stream_name(order_id))
        link_transfer(payment.transfer_id, events.last) if payment
        outcome(order, payment:, warnings:, dry_run: false, events:)
      end
    end

    # 銀行の振込が終わった（Shop::PaymentJob から呼ばれる）。商店の振込でなければ何もしない。
    # 何度呼ばれても1回分しか動かない（注文の状態で判定し、同時に動いたら後の方が負けてやり直す）
    def settle_transfer(transfer_id, completed:, reason: nil)
      link = @event_store.read.stream(transfer_stream(transfer_id)).first
      return unless link

      order = load_order(link.data.fetch(:order_id))
      case link
      when Events::OrderPaymentRequested then settle_payment(order, transfer_id, completed:, reason:)
      when Events::OrderRefundRequested then settle_refund(order, transfer_id, completed:, reason:)
      end
      order
    end

    def load_order(id) = @repository.load(Order.new(id), Order.stream_name(id))

    def load_product(sku) = @repository.load(Product.new(sku), Product.stream_name(sku))

    private

    def settle_payment(order, transfer_id, completed:, reason:)
      return unless order.payment_pending? && order.payment_transfer_id == transfer_id
      return store_order(order) { order.fail_payment!(reason: reason || "支払いの振込ができませんでした") } unless completed

      transaction do
        order.mark_paid!
        products = allocate(order)
        refund = nil
        if products
          order.fulfill!
        else
          refund = refund(order)
        end
        events = order.unpublished_events.to_a
        products&.each { @repository.store(it, Product.stream_name(it.sku)) }
        @repository.store(order, Order.stream_name(order.id))
        link_transfer(refund.transfer_id, events.find { it.is_a?(Events::OrderRefundRequested) }) if refund
      end
    end

    def settle_refund(order, transfer_id, completed:, reason:)
      return unless order.refunding? && order.refund_transfer_id == transfer_id

      store_order(order) do
        completed ? order.mark_refunded! : order.fail_refund!(reason: reason || "返金の振込ができませんでした")
      end
    end

    # 注文のすべての行を引き当てる。1つでも足りなければ、どれも引き当てずに nil（注文はキャンセル済みにする）
    def allocate(order)
      order.lines.group_by(&:sku).map do |sku, lines|
        load_product(sku).tap { it.allocate(order_id: order.id, quantity: lines.sum(&:quantity)) }
      end
    rescue OutOfStock, NotFound => e
      order.cancel!(reason: e.message)
      nil
    end

    # 商店の口座から購入者へ返金の振込を頼む。頼めなければ返金失敗（人の手で対応）
    def refund(order)
      memo = "#{SHOP_NAME} 返金 #{order.id.first(8)}"
      pay(order, refund: true) { @bank.transfer(account_number, order.buyer_account, order.total, memo:, holdable: false) }
        &.tap { order.request_refund(it.transfer_id) }
    end

    # 銀行に振込を頼む。業務エラー（残高不足・凍結など）なら注文を失敗にして nil を返す。
    # 同時更新（ConcurrentModification）は書き込みの途中で起きるので、握りつぶさずにトランザクションごと戻す
    def pay(order, refund: false)
      yield
    rescue Banking::ConcurrentModification
      raise
    rescue Banking::Error, ArgumentError => e
      refund ? order.fail_refund!(reason: e.message) : order.fail_payment!(reason: e.message)
      nil
    end

    def change_product(sku, dry_run:)
      product = load_product(sku.to_s)
      yield product
      events = product.unpublished_events.to_a
      transaction { @repository.store(product, Product.stream_name(product.sku)) } unless dry_run
      events
    end

    def store_order(order)
      yield
      transaction { @repository.store(order, Order.stream_name(order.id)) }
    end

    def outcome(order, payment:, warnings:, dry_run:, events: order.unpublished_events.to_a)
      Outcome.new(order_id: order.id, status: order.status, total: order.total, events:, payment:, warnings:,
                  dry_run:)
    end

    # 振込IDから注文を引けるようにする
    def link_transfer(transfer_id, event)
      @event_store.link(event.event_id, stream_name: transfer_stream(transfer_id))
    end

    def transfer_stream(transfer_id) = "ShopTransfer$#{transfer_id}"

    # 銀行の振込も含めて1つのトランザクションで保存する（Bank の中のトランザクションはこれに合流する）。
    # どれかが同時更新で負けたら全部取り消し
    def transaction(**metadata, &)
      ActiveRecord::Base.transaction do
        @event_store.with_metadata(actor: @actor, **metadata, &)
      end
    rescue RubyEventStore::WrongExpectedEventVersion
      raise ConcurrentModification, "注文か在庫が同時に更新されました。もう一度やり直してください"
    end
  end
end
