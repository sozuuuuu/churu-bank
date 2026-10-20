# 利用者画面。自分の口座だけ（コントローラ側で Current.user の口座に絞る）
scope module: :customer do
  root "accounts#index"

  resources :accounts, only: %i[index show], param: :number do
    member do
      get :balance # 時点指定の残高（Turbo Frame で差し替え）
    end
    # 振込（確認 → 確定の2段階）。入出金と凍結は行員だけ
    resources :transfers, only: %i[new create], module: :accounts
  end
end
