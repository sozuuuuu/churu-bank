# 利用者画面（ネットバンキング。コントローラは Netbank::。利用者のモデル Customer と名前がぶつからないように）。自分の口座だけ（コントローラ側で current_customer の口座に絞る）
scope module: :netbank do
  root "accounts#index"

  resources :accounts, only: %i[index show], param: :number do
    member do
      get :balance # 時点指定の残高（Turbo Frame で差し替え）
    end
    # 振込（確認 → 確定の2段階）。入金と凍結は行員だけ。出金は下の出金依頼から
    resources :transfers, only: %i[new create], module: :accounts
    # 出金の依頼（確認 → 確定の2段階）。行員が窓口で処理する前なら取り消せる（DELETE）
    resources :withdrawal_requests, only: %i[new create destroy], module: :accounts
    # 実行前（予約中・保留中）の自分の振込の取消（確認 → 確定の2段階）
    resources :transfers, only: [], module: :accounts do
      resource :cancellation, only: %i[new create]
    end
  end
end

# わたしの出来事（イベント）: 自分の口座にかかわる出来事だけを日本語で・図で見る（MyEvents::。表示の部品は packs/event_lens）
scope module: :my_events do
  get "events/time_machine" => "events#time_machine", as: :event_time_machine
  resources :events, only: %i[index show]
end
