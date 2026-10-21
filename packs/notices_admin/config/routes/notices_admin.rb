# お知らせの管理（packs/notices_admin）: /admin/notices（作成・編集・掲載終了）。
# NoticesAdmin::ApplicationController で行員だけに絞る。ルート名は notices_admin_*
scope "admin", module: "notices_admin", as: "notices_admin" do
  resources :notices, only: %i[index new create edit update] do
    resource :closing, only: :create # 掲載を終える（ends_at を今に）
  end
end
