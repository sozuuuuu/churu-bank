# 町の動かし方（表 simulation_controls の1行だけ）。画面（Puma）と町を動かす係（別のプロセス）は、この行でやりとりする
module Simulation
  class Control < ApplicationRecord
    self.table_name = "simulation_controls"

    # 1日を何秒にするか（画面の選択肢）
    SPEEDS = { 12 => "とても速い（1日 12 秒）", 24 => "ふつう（1日 24 秒）", 48 => "ゆっくり（1日 48 秒）",
               96 => "のんびり（1日 96 秒）" }.freeze
    TIMES = { "morning" => "朝", "noon" => "昼", "evening" => "夕方", "night" => "夜" }.freeze
    # この秒数より前の heartbeat なら、町を動かす係は止まっているとみなす
    ALIVE_WITHIN = 5.seconds

    validates :seconds_per_day, inclusion: { in: SPEEDS.keys }

    def self.current = first || create!

    def keeper_alive? = heartbeat_at.present? && heartbeat_at > ALIVE_WITHIN.ago

    def time_label = TIMES[time]

    # 画面に出す、町のいまの様子
    def status_label
      return "町を動かす係が止まっています（bin/rails churu:simulate を動かしてください）" unless keeper_alive?
      return "止まっています" if !running && !town_running
      return "起こしています…" if running && !town_running
      return "止めています…" if !running && town_running

      time_label ? "動いています（#{day} 日目の#{time_label}）" : "動いています（時計の合図を待っています）"
    end
  end
end
