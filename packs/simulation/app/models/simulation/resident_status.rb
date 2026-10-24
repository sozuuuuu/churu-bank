# 住民ごとの様子（表 simulation_residents）。住民の Ractor の中の記憶そのものではなく、住民が役場へ出した Report の写し。
# 役場（メインの Ractor）だけが書き、画面が読む。お金の正はイベントストア（money は住民の「見込み」）
module Simulation
  class ResidentStatus < ApplicationRecord
    self.table_name = "simulation_residents"

    belongs_to :customer

    def temperament_label = Temperament.fetch(temperament).label

    # 気分 → ねこの顔（Ui::ThemeHelper#cat）
    def face
      return :surprised if restarts.positive? && last_action.to_s.start_with?("見張り役")
      return :normal if mood.nil?

      if mood >= 70 then :happy
      elsif mood >= 35 then :normal
      else :sad
      end
    end
  end
end
