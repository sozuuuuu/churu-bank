# イベントビューア（packs/event_viewer）: /admin/events。EventViewer::ApplicationController で行員だけに絞る。
# ルート名は event_viewer_*。英語の RES Browser（/res）は「詳しく見る（英語）」として残してある
scope "admin/events", module: "event_viewer", as: "event_viewer" do
  resource :time_machine, only: :show # 口座の残高を、出来事を1件ずつ足して確かめる
  resources :lanes, only: :index      # 振込・注文などを選んで、関係者のレーン図
end
scope "admin", module: "event_viewer", as: "event_viewer" do
  resources :events, only: %i[index show] # 一覧と生中継・1件の中身とつながりの図
end
