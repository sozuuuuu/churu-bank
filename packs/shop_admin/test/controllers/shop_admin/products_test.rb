require "test_helper"

# 商品と在庫の管理（/shop/admin）は行員だけ
class ShopAdmin::ProductsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @store = Shop::Store.new(actor: "test")
    @store.open_shop
    @store.register_product(sku: "churu", name: "ちゅ〜る", emoji: "🐟", price: 30)
    @store.restock("churu", 5)
    @staff = create_staff
  end

  test "利用者のログインでは商品と在庫の管理ができない（行員のログイン画面へ）" do
    sign_in_as_customer create_customer(name: "オルカ")

    get shop_admin_products_path
    assert_redirected_to new_staff_session_path
    post shop_admin_products_path, params: { sku: "jarashi", name: "猫じゃらし", price: "120" }
    assert_redirected_to new_staff_session_path
    post shop_admin_product_restock_path("churu"), params: { quantity: "3" }
    assert_redirected_to new_staff_session_path
    patch shop_admin_product_path("churu"), params: { price: "1" }
    assert_redirected_to new_staff_session_path
    post shop_admin_opening_path
    assert_redirected_to new_staff_session_path

    product = ShopProduct.find_by!(sku: "churu")
    assert_equal [ 30, 5 ], [ product.price, product.stock ]
    assert_not ShopProduct.exists?(sku: "jarashi")
  end

  test "行員は商品を登録して入荷できる。見た目は管理画面、注文は全員分見られる" do
    bank = Banking::Bank.new(actor: "test")
    mike = create_customer(name: "ミケ")
    mike_number = bank.open_account(holder_name: "ミケ").account_number
    mike.grant_account(mike_number)
    bank.deposit(mike_number, 1000)
    order = @store.place_order(order_id: SecureRandom.uuid, buyer_account: mike_number, items: { "churu" => 1 })
    sign_in_as_staff @staff

    post shop_admin_products_path, params: { sku: "jarashi", name: "猫じゃらし", emoji: "🪶", price: "120" }
    post shop_admin_product_restock_path("jarashi"), params: { quantity: "3" }
    patch shop_admin_product_path("jarashi"), params: { price: "100" }
    follow_redirect!

    assert_response :success
    product = ShopProduct.find_by!(sku: "jarashi")
    assert_equal [ 100, 3 ], [ product.price, product.stock ]
    assert_select "#shop_product_#{product.id}", /猫じゃらし/
    assert_select "a[href=?]", shop_admin_order_path(order.order_id)
    assert_no_match "ui/cat", response.body
    assert_equal @staff.actor, Rails.configuration.event_store.read.stream("Product$jarashi").last.metadata[:actor]

    get shop_admin_order_path(order.order_id)
    assert_response :success
    assert_match "RES Browser で見る", response.body
  end
end
