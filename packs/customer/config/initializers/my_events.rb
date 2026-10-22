# 利用者の「わたしの出来事」の生中継: どのパックのイベントでも、コミットされたら見てよい利用者の一覧に1件足す
# （読むだけ。イベントストアには何も書かない）。イベントストア本体はルートの config/initializers/event_store.rb が作る
Rails.configuration.to_prepare do
  Rails.configuration.event_store.subscribe_to_all_events(MyEvents::EventsLiveJob)
end
