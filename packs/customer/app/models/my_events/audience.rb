# 出来事1件を見てよい口座と利用者（索引 FeedEntry・生中継・ねこの実況の配信先）。
# かかわる口座（data の口座番号と、振込・注文・出金依頼・ローンの読み取りモデルから引いた口座番号）のうち、
# EventScope がその口座1つだけで通すもの（振込の引き落としは振込元だけ、入金は振込先だけ、など）
module MyEvents
  module Audience
    # 見てよい口座番号
    def self.accounts(event)
      candidates(event).select { EventScope.new([ it ], eager: false).visible?(event) }
    end

    # 見てよい利用者（見てよい口座のどれかの持ち主）
    def self.of(event)
      accounts(event).flat_map { ::Customer.owning(it).to_a }.uniq
    end

    def self.candidates(event)
      data = event.data
      numbers = data.values_at(:account_number, :from_account, :to_account, :buyer_account)
      if (transfer = data[:transfer_id] && ::Transfer.find_by(transfer_id: data[:transfer_id]))
        numbers += [ transfer.from_account, transfer.to_account ]
      end
      numbers << ::ShopOrder.find_by(order_id: data[:order_id])&.buyer_account if data[:order_id]
      numbers << ::WithdrawalRequest.find_by(request_id: data[:request_id])&.account_number if data[:request_id]
      numbers << ::Loan.find_by(loan_id: data[:loan_id])&.account_number if data[:loan_id]
      numbers.compact.map(&:to_s).uniq
    end
    private_class_method :candidates
  end
end
