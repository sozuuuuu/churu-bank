# いまだれがつないでいるか（在席）。Action Cable の購読ごとに1行で、subscribed で足し、unsubscribed で消す。
# 同じ人がタブを2つ開いていれば2行（1つ閉じてもまだ在席）。サーバーが落ちると unsubscribed が呼ばれず行が残るので、
# サーバーの起動時に全部消す（config/initializers/counter.rb）
class CounterPresence < ApplicationRecord
  LOBBY = "lobby" # 窓口の列（/admin/counter/queue）を開いている行員

  scope :in_room, ->(room) { where(room:) }
end
