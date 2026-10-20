# 注文のプロセスマネージャ。銀行の TransferCompleted / TransferFailed がコミットされたら Solid Queue に積まれ、
# それが商店の振込（支払い・返金）なら注文を先に進める。銀行は商店を知らないので、
# 「どの振込が商店のものか」は商店の側（Shop::Store#settle_transfer）で判定する。
#
# - CorrelatedHandler で correlation_id / causation_id を引き継ぐので、RES Browser で
#   注文 → 振込 → 入金 → 引き当て（または返金）を1本の流れとして辿れる
# - settle_transfer は何度呼ばれても1回分しか動かないので、リトライしても二重に引き当て・返金しない
module Shop
  class PaymentJob < ApplicationJob
    prepend RailsEventStore::CorrelatedHandler
    prepend RailsEventStore::AsyncHandler

    queue_as :default

    # 同じ注文・商品・口座に同時に書き込みがあって負けたら、少し待ってやり直す
    retry_on Shop::ConcurrentModification, Banking::ConcurrentModification, wait: 1.second, attempts: 5

    def perform(event)
      Shop::Store.new(actor: "shop-payment").settle_transfer(
        event.data.fetch(:transfer_id),
        completed: event.is_a?(Banking::Events::TransferCompleted),
        reason: event.data[:reason]
      )
    end
  end
end
