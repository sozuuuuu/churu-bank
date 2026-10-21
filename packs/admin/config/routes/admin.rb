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

# 取消・組戻し・利息の手動実行。どれも理由や日付の入力 → 確認（ドライラン）→ 確定の2段階
namespace :admin do
  scope "accounts/:account_number", module: :accounts, as: :account do
    resources :reversals, only: %i[new create] # 入出金の取消（?event_id= で通帳の行を指す）
    resource :interest, only: %i[new create]   # この口座だけ利息を払う
  end
  resources :transfers, only: [] do
    resources :reversals, only: %i[new create], module: :transfers # 完了した振込の組戻し
    resource :release, only: %i[new create], module: :transfers    # 保留中の振込を通す
    resource :stop, only: %i[new create], module: :transfers       # 実行前（予約中・保留中）の振込の差し止め
  end
  resource :interest, only: %i[show create] # 利率の表示と、全口座の利息
end

# イベントストアの中身を見るブラウザ（RES Browser）。管理者以外には 404
constraints(Authentication::AdminConstraint) do
  mount RubyEventStore::Browser::App.for(event_store_locator: -> { Rails.configuration.event_store }), at: "/res"
end
