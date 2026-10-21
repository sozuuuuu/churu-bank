# ちゅ〜る商店の管理（packs/shop_admin）。行員だけ（ShopAdmin::ApplicationController）。ルート名は shop_admin_*
scope "shop/admin", module: "shop_admin", as: "shop_admin" do
  resource :opening, only: :create # 商店の口座を開く
  resources :products, only: %i[index create update], param: :sku do
    resource :restock, only: :create
  end
  resources :orders, only: :show, param: :order_id # 注文（全員分）
end
