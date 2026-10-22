# ねこの実況（/admin/events/commentary）: 銀行で起きた出来事を、ちゅーるがぜんぶ実況する。
# 開いたときは最近の出来事を実況の文で並べ、あとは CommentaryJob が1行ずつ届ける。この画面だけねこテーマ（セリフ窓がしゃべる）
module EventViewer
  class CommentariesController < ApplicationController
    RECENT = 20

    def show
      @events = Rails.configuration.event_store.read.backward.limit(RECENT).to_a
      @commentary = EventLens::Commentary.new(names:)
    end
  end
end
