require "test_helper"

# 画面の流れ: 購入者を選ぶ → カートに入れる → 確認（ドライラン）→ 注文 → ジョブで完了
class Shop::ShoppingTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @store = Shop::Store.new(actor: "test")
    @shop = @store.open_shop
    bank = Banking::Bank.new(actor: "test")
    @orca = bank.open_account(holder_name: "オルカ").account_number
    bank.deposit(@orca, 1000)
    @store.register_product(sku: "churu", name: "ちゅ〜る", emoji: "🐟", price: 30)
    @store.restock("churu", 5)
  end

  def drain
    10.times do
      break if enqueued_jobs.empty?

      perform_enqueued_jobs
    end
  end

  test "注文して、支払いが終わると完了になる" do
    get shop_root_path
    assert_response :success
    assert_select ".shop-product h2", "ちゅ〜る"

    patch shop_buyer_path, params: { account_number: @orca }
    post shop_cart_items_path, params: { sku: "churu", quantity: 2 }
    follow_redirect!
    assert_select ".shop-cart", /60 ちゅ〜る/

    post shop_orders_path, params: { preview: "1" }
    assert_response :success
    assert_select "turbo-frame#checkout input[name=order_id]"
    order_id = css_select("input[name=order_id]").first["value"]

    post shop_orders_path, params: { order_id:, items: { churu: 2 } }
    assert_redirected_to shop_order_path(order_id)

    # 確定が2回送られても、注文は1つ
    post shop_orders_path, params: { order_id:, items: { churu: 2 } }
    assert_redirected_to shop_order_path(order_id)
    assert_equal 1, ShopOrder.count

    drain
    get shop_order_path(order_id)
    assert_select ".badge", "完了"
    assert_select "code", "OrderFulfilled"
    assert_equal 3, ShopProduct.find_by!(sku: "churu").stock
  end

  test "確認で残高不足ならその場でエラーを出す" do
    patch shop_buyer_path, params: { account_number: @orca }
    post shop_orders_path, params: { preview: "1", items: { churu: 40 } }

    assert_response :unprocessable_entity
    assert_select ".flash-alert", /残高不足/
  end

  test "管理画面で商品を登録して入荷する" do
    post shop_admin_products_path, params: { sku: "jarashi", name: "猫じゃらし", emoji: "🪶", price: "120" }
    post shop_admin_product_restock_path("jarashi"), params: { quantity: "3" }
    patch shop_admin_product_path("jarashi"), params: { price: "100" }
    follow_redirect!

    assert_response :success
    product = ShopProduct.find_by!(sku: "jarashi")
    assert_equal [ 100, 3 ], [ product.price, product.stock ]
    assert_select "#shop_product_#{product.id}", /猫じゃらし/
  end

  test "注文履歴" do
    get shop_orders_path
    assert_response :success
  end
end
