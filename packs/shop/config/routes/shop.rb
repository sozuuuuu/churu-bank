# ちゅ〜る商店（packs/shop）の画面。ルートの config/routes.rb の `draw :shop` で読み込まれる
# （packs-rails がパックの config/routes を探す場所に足している）
scope "shop", module: "shop", as: "shop" do
  root "products#index"

  # 購入者（ログイン中の利用者の口座のどれで払うか）
  resource :buyer, only: :update
  # カート（セッションに持つ）
  resources :cart_items, only: %i[create destroy], param: :sku, path: "cart"
  # 注文。create は確認（preview=1 でドライラン）→ 確定の2段階
  resources :orders, only: %i[index show create], param: :order_id

  # 商品と在庫の管理。行員だけ（Shop::Admin::ApplicationController）
  namespace :admin do
    resource :opening, only: :create # 商店の口座を開く
    resources :products, only: %i[index create update], param: :sku do
      resource :restock, only: :create
    end
  end
end
