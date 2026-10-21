require "test_helper"

# 画面の流れ: ログイン → カートに入れる → 確認（ドライラン）→ 注文 → ジョブで完了
class Shop::ShoppingTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @store = Shop::Store.new(actor: "test")
    @shop = @store.open_shop
    bank = Banking::Bank.new(actor: "test")
    @orca = create_user(name: "オルカ")
    @orca_number = bank.open_account(holder_name: "オルカ").account_number
    @orca.grant_account(@orca_number)
    bank.deposit(@orca_number, 1000)
    @mike = create_user(name: "ミケ")
    @mike_number = bank.open_account(holder_name: "ミケ").account_number
    @mike.grant_account(@mike_number)
    bank.deposit(@mike_number, 1000)
    @staff = create_user(name: "行員", admin: true)
    @store.register_product(sku: "churu", name: "ちゅ〜る", emoji: "🐟", price: 30)
    @store.restock("churu", 5)
  end

  def drain
    10.times do
      break if enqueued_jobs.empty?

      perform_enqueued_jobs
    end
  end

  def place_order(order_id: SecureRandom.uuid)
    post shop_orders_path, params: { order_id:, items: { churu: 1 } }
    order_id
  end

  test "ログインしていなければログイン画面へ" do
    get shop_root_path
    assert_redirected_to new_session_path

    post shop_orders_path, params: { items: { churu: 1 } }
    assert_redirected_to new_session_path
    assert_equal 0, ShopOrder.count
  end

  test "注文して、支払いが終わると完了になる" do
    sign_in_as @orca
    get shop_root_path
    assert_response :success
    assert_select ".shop-product h2", "ちゅ〜る"
    assert_select ".shop-buyer", /#{@orca_number}/ # 支払う口座は自分の口座
    assert_match "ui/cat", response.body # 利用者にはねこテーマ
    assert_select "a[href=?]", shop_admin_products_path, count: 0

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
    assert_equal @orca_number, ShopOrder.sole.buyer_account

    drain
    get shop_order_path(order_id)
    assert_select ".badge", "完了"
    assert_select "code", "OrderFulfilled"
    assert_equal 3, ShopProduct.find_by!(sku: "churu").stock
    assert_equal 940, Account.find_by!(number: @orca_number).balance
  end

  test "確認で残高不足ならその場でエラーを出す" do
    sign_in_as @orca
    post shop_orders_path, params: { preview: "1", items: { churu: 40 } }

    assert_response :unprocessable_entity
    assert_select ".flash-alert", /残高不足/
  end

  test "他人の口座は支払う口座に選べず、他人の口座で注文できない" do
    sign_in_as @orca
    patch shop_buyer_path, params: { account_number: @mike_number }
    assert_equal "その口座では買えません", flash[:alert]

    place_order
    drain

    assert_equal [ @orca_number ], ShopOrder.pluck(:buyer_account)
    assert_equal 1000, Account.find_by!(number: @mike_number).balance
  end

  test "口座がひも付いていなければ注文できない" do
    sign_in_as create_user(name: "口座なし")
    place_order

    assert_redirected_to shop_root_path
    assert_equal "買い物に使える口座がありません", flash[:alert]
    assert_equal 0, ShopOrder.count
  end

  test "注文履歴は自分の口座の分だけ。他人の注文は 404" do
    sign_in_as @mike
    mike_order = place_order
    sign_in_as @orca
    orca_order = place_order

    get shop_orders_path
    assert_response :success
    assert_select "a[href=?]", shop_order_path(orca_order)
    assert_select "a[href=?]", shop_order_path(mike_order), count: 0

    get shop_order_path(mike_order)
    assert_response :not_found
  end

  test "利用者は商品と在庫の管理ができない（404）" do
    sign_in_as @orca

    get shop_admin_products_path
    assert_response :not_found
    post shop_admin_products_path, params: { sku: "jarashi", name: "猫じゃらし", price: "120" }
    assert_response :not_found
    post shop_admin_product_restock_path("churu"), params: { quantity: "3" }
    assert_response :not_found
    patch shop_admin_product_path("churu"), params: { price: "1" }
    assert_response :not_found
    post shop_admin_opening_path
    assert_response :not_found

    product = ShopProduct.find_by!(sku: "churu")
    assert_equal [ 30, 5 ], [ product.price, product.stock ]
    assert_not ShopProduct.exists?(sku: "jarashi")
  end

  test "行員は商品を登録して入荷できる。見た目は管理画面、注文は全員分見られる" do
    sign_in_as @mike
    mike_order = place_order
    sign_in_as @staff

    post shop_admin_products_path, params: { sku: "jarashi", name: "猫じゃらし", emoji: "🪶", price: "120" }
    post shop_admin_product_restock_path("jarashi"), params: { quantity: "3" }
    patch shop_admin_product_path("jarashi"), params: { price: "100" }
    follow_redirect!

    assert_response :success
    product = ShopProduct.find_by!(sku: "jarashi")
    assert_equal [ 100, 3 ], [ product.price, product.stock ]
    assert_select "#shop_product_#{product.id}", /猫じゃらし/
    assert_no_match "ui/cat", response.body

    get shop_order_path(mike_order)
    assert_response :success
  end

  test "行員も自分にひも付いた口座でだけ買える" do
    sign_in_as @staff
    patch shop_buyer_path, params: { account_number: @orca_number }
    place_order

    assert_redirected_to shop_root_path
    assert_equal 0, ShopOrder.count
  end
end
