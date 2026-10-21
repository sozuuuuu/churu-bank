require "test_helper"

# 商店: 注文 → 銀行の振込（購入者 → 商店）→ Shop::PaymentJob が在庫を引き当てて完了。
# 在庫が足りなければ返金（商店 → 購入者）してキャンセル
class Shop::StoreTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @bank = Banking::Bank.new(actor: "test")
    @store = Shop::Store.new(actor: "test")
    @shop = @store.open_shop
    @orca = @bank.open_account(holder_name: "オルカ").account_number
    @zingiber = @bank.open_account(holder_name: "ジンジベル").account_number
    @bank.deposit(@orca, 1000)
    @bank.deposit(@zingiber, 1000)
    @store.register_product(sku: "churu", name: "ちゅ〜る", emoji: "🐟", price: 30)
    @store.register_product(sku: "tsumetogi", name: "爪とぎ", price: 300)
    @store.restock("churu", 10)
    @store.restock("tsumetogi", 1)
    drain
  end

  def event_store = Rails.configuration.event_store
  def balance(number) = Account.find_by!(number:).balance
  def stock(sku) = ShopProduct.find_by!(sku:).stock
  def order(id) = ShopOrder.find_by!(order_id: id)

  # ジョブが次のジョブを積む（銀行の入金 → 商店の引き当て → 返金の入金 → …）ので、空になるまで流す
  def drain
    10.times do
      break if enqueued_jobs.empty?

      perform_enqueued_jobs
    end
  end

  def place(buyer, items, order_id: SecureRandom.uuid, **)
    @store.place_order(order_id:, buyer_account: buyer, items:, **)
  end

  test "商店の口座は1回しか開かない" do
    assert_equal @shop, @store.open_shop
    assert_equal 1, Account.where(holder_name: "ちゅ〜る商店").count
  end

  test "支払いが終わると在庫を引き当てて完了する" do
    outcome = place(@orca, { "churu" => 3, "tsumetogi" => 1 })

    assert_equal "payment_pending", order(outcome.order_id).status
    assert_equal 390, outcome.total
    assert_equal 610, balance(@orca)
    assert_equal 0, balance(@shop)

    drain

    assert_equal "fulfilled", order(outcome.order_id).status
    assert_equal 390, balance(@shop)
    assert_equal [ 7, 0 ], [ stock("churu"), stock("tsumetogi") ]
    assert_equal [ [ "churu", 30, 3 ], [ "tsumetogi", 300, 1 ] ],
                 order(outcome.order_id).lines.map { [ it.sku, it.unit_price, it.quantity ] }
  end

  test "高額振込の保留のしきい値を超えても、商店の支払い・返金は保留にならない" do
    @store.restock("tsumetogi", 1)
    first = place(@orca, { "tsumetogi" => 2 }) # 600（しきい値以上）
    second = place(@zingiber, { "tsumetogi" => 1 }) # 在庫切れ → 返金も 300
    assert_operator first.total, :>=, Banking::Bank.hold_threshold
    assert_empty first.warnings
    drain

    assert_equal [ "fulfilled", "refunded" ], [ order(first.order_id).status, order(second.order_id).status ]
    assert_empty Transfer.where(status: "held")
    assert_equal [ 400, 1000 ], [ balance(@orca), balance(@zingiber) ]
  end

  test "注文の値段は注文したときのもので残る" do
    outcome = place(@orca, { "churu" => 1 })
    @store.change_price("churu", 50)
    drain

    assert_equal 30, order(outcome.order_id).lines.first.unit_price
    assert_equal 970, balance(@orca)
  end

  test "残高が足りなければ支払い失敗で残り、お金も在庫も動かない" do
    @bank.withdraw(@orca, 990)

    outcome = place(@orca, { "churu" => 1 })
    drain

    assert_equal "payment_failed", order(outcome.order_id).status
    assert_match "残高不足", order(outcome.order_id).failure_reason
    assert_nil outcome.payment
    assert_equal 10, balance(@orca)
    assert_equal 10, stock("churu")
    assert_equal 0, Transfer.count
  end

  test "支払いの振込が組戻しになったら（商店の口座が凍結中）支払い失敗になる" do
    @bank.freeze_account(@shop, reason: "棚卸し")

    outcome = place(@orca, { "churu" => 1 })
    drain

    assert_equal "payment_failed", order(outcome.order_id).status
    assert_match "凍結", order(outcome.order_id).failure_reason
    assert_equal 1000, balance(@orca)
    assert_equal 10, stock("churu")
  end

  test "支払い後に在庫が足りなければ、キャンセルして返金する" do
    first = place(@orca, { "tsumetogi" => 1 })
    second = place(@zingiber, { "tsumetogi" => 1, "churu" => 2 })
    assert_empty first.warnings
    drain

    assert_equal "fulfilled", order(first.order_id).status
    assert_equal "refunded", order(second.order_id).status
    assert_match "在庫が足りません", order(second.order_id).failure_reason
    assert_equal [ 700, 1000 ], [ balance(@orca), balance(@zingiber) ]
    assert_equal 300, balance(@shop)
    # 足りなかった注文は、ほかの行（ちゅ〜る）も引き当てない
    assert_equal [ 0, 10 ], [ stock("tsumetogi"), stock("churu") ]
    assert_equal %w[deposit transfer_out transfer_in],
                 LedgerEntry.where(account_number: @zingiber).order(:id).pluck(:kind)
  end

  test "在庫より多く注文すると、確認の時点で返金になると警告する" do
    outcome = place(@orca, { "tsumetogi" => 2 }, dry_run: true)

    assert_match "支払い後にキャンセル・返金", outcome.warnings.first
  end

  test "返金先の口座が凍結中なら返金失敗（要対応）で止まり、お金は商店に戻る" do
    outcome = place(@zingiber, { "tsumetogi" => 2 })
    perform_enqueued_jobs(except: Shop::PaymentJob) # 銀行の入金まで（商店の処理はまだ）
    @bank.freeze_account(@zingiber, reason: "テスト")
    drain

    assert_equal "refund_failed", order(outcome.order_id).status
    assert_equal 600, balance(@shop)
    assert_equal 400, balance(@zingiber)
  end

  test "同じ注文IDで2回注文しても、2回目は受け付けず二重に払わない" do
    order_id = SecureRandom.uuid
    place(@orca, { "churu" => 1 }, order_id:)

    assert_raises(Shop::AlreadyPlaced) { place(@orca, { "churu" => 1 }, order_id:) }
    drain

    assert_equal 1, ShopOrder.count
    assert_equal 1, Transfer.where(from_account: @orca).count
    assert_equal 970, balance(@orca)
  end

  test "支払い完了の処理が2回動いても、引き当ても返金も1回分だけ" do
    ok = place(@orca, { "churu" => 1 })
    short = place(@zingiber, { "tsumetogi" => 2 })
    perform_enqueued_jobs(except: Shop::PaymentJob) # 銀行の入金まで

    [ ok, short ].each do |outcome|
      2.times { @store.settle_transfer(outcome.payment.transfer_id, completed: true) }
    end
    drain
    @store.settle_transfer(@store.load_order(short.order_id).refund_transfer_id, completed: true)

    assert_equal 9, stock("churu")
    assert_equal 1, Transfer.where(from_account: @shop).count
    assert_equal 1000, balance(@zingiber)
    assert_equal [ "fulfilled", "refunded" ], [ order(ok.order_id).status, order(short.order_id).status ]
  end

  test "商店と関係ない振込では何もしない" do
    transfer = @bank.transfer(@orca, @zingiber, 10)
    drain

    assert_nil @store.settle_transfer(transfer.transfer_id, completed: true)
    assert_equal 0, ShopOrder.count
  end

  test "ドライランは何も書き込まない" do
    outcome = place(@orca, { "churu" => 2 }, dry_run: true)

    assert_equal [ 1000, 940 ], [ outcome.payment.balance_before, outcome.payment.balance_after ]
    assert_equal %w[OrderPlaced OrderPaymentRequested], outcome.events.map { it.class.name.demodulize }
    assert_equal 0, ShopOrder.count
    assert_equal 0, Transfer.count
  end

  test "ドライランで残高不足なら、その場でわかる" do
    assert_raises(Banking::InsufficientFunds) { place(@orca, { "tsumetogi" => 4 }, dry_run: true) }
  end

  test "注文から引き当てまで、同じ correlation_id で辿れる" do
    outcome = place(@orca, { "churu" => 1 })
    drain

    placed = event_store.read.stream("Order$#{outcome.order_id}").first
    allocated = event_store.read.stream("Product$churu").of_type(Shop::Events::StockAllocated).last
    fulfilled = event_store.read.stream("Order$#{outcome.order_id}").last
    assert_equal placed.correlation_id, allocated.correlation_id
    assert_kind_of Shop::Events::OrderFulfilled, fulfilled
    assert_equal "shop-payment", fulfilled.metadata[:actor]
  end

  test "商品と在庫の入力チェック" do
    assert_raises(Shop::AlreadyListed) { @store.register_product(sku: "churu", name: "ちゅ〜る", price: 30) }
    assert_raises(ArgumentError) { @store.register_product(sku: "x y", name: "だめ", price: 1) }
    assert_raises(ArgumentError) { @store.restock("churu", 0) }
    assert_raises(Shop::NotFound) { @store.restock("nothing", 1) }
    assert_raises(Shop::NotFound) { place(@orca, { "nothing" => 1 }) }
    assert_raises(ArgumentError) { place(@orca, {}) }
  end
end
