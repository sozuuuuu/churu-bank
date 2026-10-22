# イベントビューアの CSS（app/assets/stylesheets/event_viewer）と Stimulus（app/javascript/controllers/event_viewer）を
# propshaft の読み込み先に足す。JS はルートの config/importmap.rb で controllers/event_viewer/* に pin している
Rails.application.config.assets.paths << Rails.root.join("packs/event_viewer/app/assets/stylesheets")
Rails.application.config.assets.paths << Rails.root.join("packs/event_viewer/app/javascript")

# 生中継: どのパックのイベントでも、コミットされたら一覧の頭に1件足す（読むだけ。イベントストアには何も書かない）。
# イベントストア本体はルートの config/initializers/event_store.rb が作る
Rails.configuration.to_prepare do
  Rails.configuration.event_store.subscribe_to_all_events(EventViewer::LiveJob)
end
