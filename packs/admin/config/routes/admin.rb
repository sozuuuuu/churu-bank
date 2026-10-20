# 管理画面（行員用）。コントローラ側で管理者だけに絞る
namespace :admin do
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
end

# イベントストアの中身を見るブラウザ（RES Browser）。管理者以外には 404
constraints(Authentication::AdminConstraint) do
  mount RubyEventStore::Browser::App.for(event_store_locator: -> { Rails.configuration.event_store }), at: "/res"
end
