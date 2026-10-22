# 利用者の「わたしの出来事」の生中継: 出来事がコミットされたら（RES の非同期ハンドラ。Solid Queue）、
# その出来事を見てよい利用者（かかわる口座の持ち主で、EventScope が通すもの）にだけ、一覧の頭に1行足す Turbo Stream を送る。
# 購読は customer_stream_from current_customer, :events（利用者の接続だけ。ほかの人のストリームは署名がちがうので購読できない）
module MyEvents
  class EventsLiveJob < ApplicationJob
    prepend RailsEventStore::AsyncHandler

    TARGET = "my_events_live".freeze

    queue_as :default

    def perform(event)
      candidates(event).each do |customer|
        next unless EventScope.new(customer.account_numbers).visible?(event)

        html = EventsController.render(partial: "event_lens/event",
                                       locals: { event:, names: EventsController.names_for(customer) })
        Turbo::StreamsChannel.broadcast_prepend_to(customer, :events, target: TARGET, html:)
      end
    end

    private

    # かかわる口座の持ち主（data の口座番号と、振込・注文・出金依頼の読み取りモデルから引いた口座番号）
    def candidates(event)
      data = event.data
      numbers = data.values_at(:account_number, :from_account, :to_account, :buyer_account)
      if (transfer = data[:transfer_id] && ::Transfer.find_by(transfer_id: data[:transfer_id]))
        numbers += [ transfer.from_account, transfer.to_account ]
      end
      numbers << ::ShopOrder.find_by(order_id: data[:order_id])&.buyer_account if data[:order_id]
      numbers << ::WithdrawalRequest.find_by(request_id: data[:request_id])&.account_number if data[:request_id]
      numbers.compact.uniq.flat_map { ::Customer.owning(it).to_a }.uniq
    end
  end
end
