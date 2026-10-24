# 行員エージェントごとの様子（表 simulation_clerks）。行員の Ractor が役場へ出した ClerkReport の写し。役場だけが書き、画面が読む
module Simulation
  class ClerkStatus < ApplicationRecord
    self.table_name = "simulation_clerks"

    ROLES = { "teller" => "窓口", "chief" => "係長" }.freeze

    belongs_to :staff

    def role_label = ROLES.fetch(role, role)

    def chief? = role == "chief"

    # 督促に出ている先の住民の名前（「こむぎの家へ督促に行った」）。窓口にいれば nil
    def visiting = state.to_s[/\A(.+)の家へ督促/, 1]
  end
end
