# 手紙の記録（表 simulation_letters）。画面の「手紙の流れ」に出す、住民・窓口役・郵便屋・見張り役のあいだの手紙。
# Ractor の受け口には「何通たまっているか」を聞けないので、役場に届いた手紙と郵便屋の写しだけを書き残す（時計の合図は数が多いので残さない）
module Simulation
  class Letter < ApplicationRecord
    self.table_name = "simulation_letters"

    KEEP = 300 # これより古いものは消す
    KINDS = {
      "ask" => "頼む", "reply" => "返事", "refuse" => "お断り", "trouble" => "助けて", "lent" => "借用書", "restart" => "起こし直し"
    }.freeze

    scope :recent, -> { order(id: :desc).limit(40) }

    def kind_label = KINDS.fetch(kind, kind)

    def self.prune!
      cutoff = order(id: :desc).offset(KEEP).pick(:id)
      where(id: ..cutoff).delete_all if cutoff
    end
  end
end
