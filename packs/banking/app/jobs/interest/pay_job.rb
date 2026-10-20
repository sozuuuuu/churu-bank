# 日次の利息。config/recurring.yml で毎日 0:05（東京）に動き、前日の終わりの残高に利息を払う。
#
# Bank#pay_interest は口座ごとに「その日の利息を払ったか」を見るので、ジョブが二重に動いても、
# 途中で失敗してリトライしても、同じ日の利息は1回だけ。
# 止まっていて動かなかった日の分は自動では払わない（必要なら date を指定して手で流す）。
module Interest
  class PayJob < ApplicationJob
    queue_as :default

    retry_on Banking::ConcurrentModification, wait: 1.second, attempts: 5

    def perform(date = Date.yesterday)
      Banking::Bank.new(actor: "interest").pay_interest(date: date.to_date)
    end
  end
end
