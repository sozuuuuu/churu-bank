# ねこの実況（行員の画面。TODO の X）: どの出来事でもコミットされたら（RES の非同期ハンドラ。Solid Queue）、
# ちゅーるのひとこと（EventLens::Commentary。名前も金額も全部出す）を、実況の画面の一覧の頭に足す Turbo Stream で配信する。
# 購読は行員の接続だけ（staff_stream_from STREAM → StaffStreamsChannel）。しゃべらせるのは画面の Stimulus（event_lens--commentary）。
# 銀行の側はこの係を知らない（出来事を購読するだけ）
module EventViewer
  class CommentaryJob < ApplicationJob
    prepend RailsEventStore::AsyncHandler

    STREAM = "event_viewer:commentary".freeze
    TARGET = "event_viewer_commentary".freeze

    queue_as :default

    def perform(event)
      line = EventLens::Commentary.new(names: ApplicationController.names).line(event)
      html = CommentariesController.render(partial: "event_lens/commentary_line", locals: { event:, line: })
      Turbo::StreamsChannel.broadcast_prepend_to(STREAM, target: TARGET, html:)
    end
  end
end
