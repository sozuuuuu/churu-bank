# 生中継: 出来事がコミットされたら（RES の非同期ハンドラ。Solid Queue）、行員のイベント一覧の頭に1行足す Turbo Stream を
# Solid Cable で配信する。購読は行員の接続だけ（staff_stream_from STREAM → StaffStreamsChannel）。
# 1件ずつふわっと入れる・止める・再開は、画面の Stimulus（event_viewer/live_controller.js）がする
module EventViewer
  class LiveJob < ApplicationJob
    prepend RailsEventStore::AsyncHandler

    STREAM = "event_viewer:events".freeze
    TARGET = "event_viewer_live".freeze

    queue_as :default

    def perform(event)
      html = EventViewer::EventsController.render(partial: "event_lens/event",
                                                  locals: { event:, names: ApplicationController.names })
      Turbo::StreamsChannel.broadcast_prepend_to(STREAM, target: TARGET, html:)
    end
  end
end
