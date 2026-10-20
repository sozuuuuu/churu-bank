Rails.application.routes.draw do
  root "accounts#index"

  resources :accounts, only: %i[index show new create], param: :number do
    member do
      get :balance # 時点指定の残高（Turbo Frame で差し替え）
    end
    # 入出金。kind=deposit|withdrawal。確認（ドライラン）→ 確定の2段階
    resources :transactions, only: %i[new create], module: :accounts
  end

  # イベントストアの中身を見るブラウザ（RES Browser）
  mount RubyEventStore::Browser::App.for(event_store_locator: -> { Rails.configuration.event_store }), at: "/res"

  get "up" => "rails/health#show", as: :rails_health_check
end
