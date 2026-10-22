# 出来事1件を見てよい利用者（生中継・ねこの実況の配信先）。
# かかわる口座（data の口座番号と、振込・注文・出金依頼の読み取りモデルから引いた口座番号）の持ち主のうち、
# EventScope が通す人だけ（振込の引き落としは振込元の人だけ、入金は振込先の人だけ、など）
module MyEvents
  module Audience
    def self.of(event)
      candidates(event).select { EventScope.new(it.account_numbers).visible?(event) }
    end

    def self.candidates(event)
      data = event.data
      numbers = data.values_at(:account_number, :from_account, :to_account, :buyer_account)
      if (transfer = data[:transfer_id] && ::Transfer.find_by(transfer_id: data[:transfer_id]))
        numbers += [ transfer.from_account, transfer.to_account ]
      end
      numbers << ::ShopOrder.find_by(order_id: data[:order_id])&.buyer_account if data[:order_id]
      numbers << ::WithdrawalRequest.find_by(request_id: data[:request_id])&.account_number if data[:request_id]
      numbers.compact.uniq.flat_map { ::Customer.owning(it).to_a }.uniq
    end
    private_class_method :candidates
  end
end
