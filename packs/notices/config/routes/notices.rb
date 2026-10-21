# 銀行からのお知らせ（packs/notices）。ルートの config/routes.rb の `draw :notices` で読み込まれる

# 行員: /admin/notices（作成・編集・掲載終了）。Notices::Admin::ApplicationController で行員だけに絞る
scope "admin", module: "notices/admin", as: "notices_admin" do
  resources :notices, only: %i[index new create edit update] do
    resource :closing, only: :create # 掲載を終える（ends_at を今に）
  end
end

# 利用者: /notices（一覧・本文。開いたら既読）と、ねこの吹き出しを閉じる
scope module: "notices" do
  resources :notices, only: %i[index show] do
    resource :dismissal, only: :create
  end
end
