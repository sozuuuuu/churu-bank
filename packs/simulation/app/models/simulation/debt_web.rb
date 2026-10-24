# 借金の関係図（画面の「だれがだれに借りているか」）のもと。住民どうしの借用書（Debt）と、銀行のちゅ〜るローン（Loan の読み取りモデル）
module Simulation
  module DebtWeb
    Edge = Data.define(:borrower, :lender, :amount)

    module_function

    # 部分テンプレート simulation/residents/_debts に渡すもの
    def locals
      residents = ResidentStatus.order(:id).to_a
      { names: residents.map(&:name), edges: edges(residents) }
    end

    def edges(residents)
      friends = Debt.web.map { |borrower, lender, amount| Edge.new(borrower:, lender:, amount:) }
      bank = residents.filter_map do |resident|
        owed = ::Loan.owed_by(resident.account_number)
        Edge.new(borrower: resident.name, lender: Letters::BANK, amount: owed) if owed.positive?
      end
      friends + bank
    end
  end
end
