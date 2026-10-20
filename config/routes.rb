Rails.application.routes.draw do
  # 画面のルートは各パックの config/routes/<名前>.rb（packs-rails が探す場所に入れてある）
  draw :identity # ログイン・ログアウト
  draw :admin    # 管理画面 /admin（と /res）
  draw :customer # 利用者画面 /

  # MCP（packs/mcp）。Streamable HTTP（stateless）。localhost からだけ受け付ける
  match "mcp" => "churu_mcp/server#handle", via: %i[get post delete], as: :mcp

  get "up" => "rails/health#show", as: :rails_health_check
end
