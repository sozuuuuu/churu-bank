# 商店のイベントがコミットされたら、商店の画面（turbo_stream_from "shop"）に Turbo の refresh を配信する。
# 銀行の画面への配信はルートの BroadcastRefreshJob が銀行のイベントから行う（商店からは触らない）
module Shop
  class BroadcastRefreshJob < ApplicationJob
    prepend RailsEventStore::AsyncHandler

    queue_as :default

    def perform(_event)
      Turbo::StreamsChannel.broadcast_refresh_to("shop")
    end
  end
end
