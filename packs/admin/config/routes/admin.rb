# 管理画面（行員用）。コントローラ側で行員だけに絞る（StaffAuthentication）
namespace :admin do
  root "accounts#index"

  resources :accounts, only: %i[index show new create], param: :number do
    member do
      get :balance # 時点指定の残高（Turbo Frame で差し替え）
    end
    # 入金（現金の持ち込み）と振込。どちらも確認（ドライラン）→ 確定の2段階。出金は窓口（出金依頼）からだけ
    resources :transactions, only: %i[new create], module: :accounts
    resources :transfers, only: %i[new create], module: :accounts
    # 凍結を「口座に1つだけあるリソース」として扱う（POST で凍結。DELETE は解除の申請で、別の行員の承認で解除される）
    resource :freeze, only: %i[create destroy], module: :accounts
  end

  resources :transfers, only: :index

  # 窓口（TODO の Q1）: 利用者の出金依頼を、行員が処理（出金）するか断る。どちらも確認 → 確定の2段階
  resources :withdrawal_requests, only: :index, path: "counter" do
    resource :processing, only: %i[new create], module: :withdrawal_requests
    resource :rejection, only: %i[new create], module: :withdrawal_requests
  end

  # 二人承認（TODO の Q2）: 承認待ちの一覧と、承認（→ 実行）・却下・取り下げ
  resources :approvals, only: :index do
    resource :grant, only: %i[new create], module: :approvals      # 承認（確認 → 確定で実行）
    resource :rejection, only: %i[new create], module: :approvals  # 却下（理由つき）
    resource :withdrawal, only: :create, module: :approvals        # 申請した本人の取り下げ
  end
end

# 取消・組戻しの申請と、利息の手動実行。どれも理由や日付の入力 → 確認（ドライラン）→ 確定の2段階。
# 取消・組戻しは「確定」で申請になり、別の行員が承認すると実行される（/admin/approvals）
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

# イベントストアの中身を見るブラウザ（RES Browser）。行員としてログインしていなければ 404
constraints(StaffAuthentication::Constraint) do
  mount RubyEventStore::Browser::App.for(event_store_locator: -> { Rails.configuration.event_store }), at: "/res"
end
