# 行員の画面だけの CSS（app/assets/stylesheets/event_viewer）を propshaft の読み込み先に足す。部品の CSS と JS は packs/event_lens
Rails.application.config.assets.paths << Rails.root.join("packs/event_viewer/app/assets/stylesheets")

# 生中継: どのパックのイベントでも、コミットされたら行員の一覧の頭に1件足す（読むだけ。イベントストアには何も書かない）。
# イベントストア本体はルートの config/initializers/event_store.rb が作る
Rails.configuration.to_prepare do
  Rails.configuration.event_store.subscribe_to_all_events(EventViewer::LiveJob)
end
