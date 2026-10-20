Rails.application.routes.draw do
  root "accounts#index"

  resources :accounts, only: %i[index show new create], param: :number do
    member do
      get :balance # 時点指定の残高（Turbo Frame で差し替え）
    end
    # 入出金（kind=deposit|withdrawal）と振込。どちらも確認（ドライラン）→ 確定の2段階
    resources :transactions, only: %i[new create], module: :accounts
    resources :transfers, only: %i[new create], module: :accounts
    # 凍結を「口座に1つだけあるリソース」として扱う（POST で凍結、DELETE で解除）
    resource :freeze, only: %i[create destroy], module: :accounts
  end

  resources :transfers, only: :index

  # イベントストアの中身を見るブラウザ（RES Browser）
  mount RubyEventStore::Browser::App.for(event_store_locator: -> { Rails.configuration.event_store }), at: "/res"

  # MCP（packs/mcp）。Streamable HTTP（stateless）。localhost からだけ受け付ける
  match "mcp" => "churu_mcp/server#handle", via: %i[get post delete], as: :mcp

  get "up" => "rails/health#show", as: :rails_health_check
end
