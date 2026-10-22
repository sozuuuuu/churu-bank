# 利用者の「わたしの出来事」の生中継: 出来事がコミットされたら（RES の非同期ハンドラ。Solid Queue）、
# その出来事を見てよい利用者（Audience。かかわる口座の持ち主で、EventScope が通すもの）にだけ、一覧の頭に1行足す Turbo Stream を送る。
# 購読は customer_stream_from current_customer, :events（利用者の接続だけ。ほかの人のストリームは署名がちがうので購読できない）
module MyEvents
  class EventsLiveJob < ApplicationJob
    prepend RailsEventStore::AsyncHandler

    TARGET = "my_events_live".freeze

    queue_as :default

    def perform(event)
      Audience.of(event).each do |customer|
        html = EventsController.render(partial: "event_lens/event",
                                       locals: { event:, names: EventsController.names_for(customer) })
        Turbo::StreamsChannel.broadcast_prepend_to(customer, :events, target: TARGET, html:)
      end
    end
  end
end
