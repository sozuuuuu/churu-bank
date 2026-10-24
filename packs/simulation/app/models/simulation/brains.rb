# 頭の種類。住民の設定（Resident::Spec の brain）には、ここの名前を書く
module Simulation
  module Brains
    def self.fetch(key) = { rules: Rules, haiku: Haiku }.fetch(key.to_sym)
  end
end
