# ちゅ〜るローンの申込と、その後（表 simulation_loan_cases）。審査・決裁は行員エージェント、貸すのは銀行（承認されてから Bank#lend）。
#   applied（たまが見る）→ forwarded（くろへ回った）→ approved（貸した。loan_id）/ rejected（断った）/ withdrawn（町が止まって取り下げ）
# 延滞: 貸したローンが返済中で、借りた日か最後に返した日から OVERDUE_DAYS 日以上たっている
module Simulation
  class LoanCase < ApplicationRecord
    self.table_name = "simulation_loan_cases"

    OVERDUE_DAYS = 6
    DUN_EVERY = 3 # 同じローンに督促状を出すのは、この日数ごと

    scope :pending, -> { where(status: %w[applied forwarded]) }
    scope :granted, -> { where(status: "approved").where.not(loan_id: nil) }

    # 延滞しているもの（today は町の何日目か）
    def self.overdue(today)
      open_ids = ::Loan.open.where(loan_id: granted.select(:loan_id)).pluck(:loan_id)
      granted.where(loan_id: open_ids).select { it.overdue?(today) }
    end

    # 督促状を出すもの（延滞していて、前の督促から DUN_EVERY 日以上）
    def self.to_dun(today) = overdue(today).select { it.last_dunned_day.nil? || today - it.last_dunned_day >= DUN_EVERY }

    def overdue?(today) = today - (last_repaid_day || decided_day || day).to_i >= OVERDUE_DAYS

    def outstanding = ::Loan.find_by(loan_id:)&.outstanding.to_i
  end
end
