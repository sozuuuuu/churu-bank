Rails.application.routes.draw do
  # 画面のルートは各パックの config/routes/<名前>.rb（packs-rails が探す場所に入れてある）
  draw :staff_identity    # 行員のログイン・ログアウト /admin/session
  draw :customer_identity # 利用者のログイン・ログアウト /session
  draw :admin             # 管理画面 /admin（と /res）
  draw :customer          # 利用者画面 /
  draw :shop              # ちゅ〜る商店 /shop
  draw :shop_admin        # 商品と在庫の管理 /shop/admin
  draw :notices           # お知らせ /notices
  draw :notices_admin     # お知らせの管理 /admin/notices

  # MCP（packs/mcp）。Streamable HTTP（stateless）。localhost からだけ受け付ける
  match "mcp" => "churu_mcp/server#handle", via: %i[get post delete], as: :mcp

  get "up" => "rails/health#show", as: :rails_health_check
end
