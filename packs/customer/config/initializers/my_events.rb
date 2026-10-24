# 利用者の「わたしの出来事」の生中継とねこの実況: どのパックのイベントでも、コミットされたら見てよい利用者にだけ届ける
# （読むだけ。イベントストアには何も書かない）。イベントストア本体はルートの config/initializers/event_store.rb が作る
Rails.configuration.to_prepare do
  Rails.configuration.event_store.subscribe_to_all_events(MyEvents::FeedJob) # 一覧の索引（my_event_entries）
  Rails.configuration.event_store.subscribe_to_all_events(MyEvents::EventsLiveJob)
  Rails.configuration.event_store.subscribe_to_all_events(MyEvents::CommentaryJob)
end
