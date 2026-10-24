# 住民どうしの借用書（表 simulation_debts）。お金の動きは銀行の振込で、こちらは「だれがだれにいくら借りているか」の町の記録。
# 返すときは古い借用書から埋めていく
module Simulation
  class Debt < ApplicationRecord
    self.table_name = "simulation_debts"

    scope :outstanding, -> { where("repaid < amount") }

    def remaining = amount - repaid

    # 借りた住民の帳面: { 貸した住民の名前 => まだ返していない額 }
    def self.owed_by(borrower)
      outstanding.where(borrower:).group(:lender).sum("amount - repaid")
    end

    # 町じゅうの借金: [ [借りた住民, 貸した住民, 額], … ]
    def self.web = outstanding.group(:borrower, :lender).sum("amount - repaid").map { |(b, l), amount| [ b, l, amount ] }

    def self.settle!(borrower:, lender:, amount:)
      left = amount
      outstanding.where(borrower:, lender:).order(:id).lock.each do |debt|
        break if left.zero?

        paid = [ debt.remaining, left ].min
        debt.update!(repaid: debt.repaid + paid)
        left -= paid
      end
    end
  end
end
