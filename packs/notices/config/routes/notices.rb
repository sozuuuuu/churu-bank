# 銀行からのお知らせ（packs/notices）。ルートの config/routes.rb の `draw :notices` で読み込まれる。
# 行員の /admin/notices は packs/notices_admin

# 利用者: /notices（一覧・本文。開いたら既読）と、ねこの吹き出しを閉じる
scope module: "notices" do
  resources :notices, only: %i[index show] do
    resource :dismissal, only: :create
  end
end
