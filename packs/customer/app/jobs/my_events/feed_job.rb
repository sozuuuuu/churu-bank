# 「わたしの出来事」の索引を足す係: 出来事がコミットされたら（RES の非同期ハンドラ。Solid Queue）、見てよい口座ぶん1行ずつ書く。
# 非同期にするのは、振込・注文・出金依頼・ローンの読み取りモデル（どの口座の出来事かを決めるのに使う）がコミットされてから見るため
module MyEvents
  class FeedJob < ApplicationJob
    prepend RailsEventStore::AsyncHandler

    queue_as :default

    def perform(event) = FeedEntry.record(event)
  end
end
