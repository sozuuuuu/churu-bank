# 振込のプロセスマネージャ。TransferDebited（引き落とし）がコミットされたら Solid Queue に積まれ、
# 振込先へ入金して完了にする。入金できなければ振込元へ組戻しして失敗にする。
#
# - AsyncHandler: ジョブの引数（シリアライズされたイベント）を RES のイベントに戻す
# - CorrelatedHandler: このジョブが出すイベントに correlation_id / causation_id を引き継ぐ
#   （RES Browser で「どのイベントがきっかけか」を辿れる）
# - settle_transfer は何度呼ばれても1回分しか動かないので、リトライしても二重入金にならない
module Transfers
  class SettleJob < ApplicationJob
    prepend RailsEventStore::CorrelatedHandler
    prepend RailsEventStore::AsyncHandler

    queue_as :default

    # 同じ口座に同時に書き込みがあって負けたら、少し待ってやり直す
    retry_on Banking::ConcurrentModification, wait: 1.second, attempts: 5

    def perform(event)
      Banking::Bank.new(actor: "transfer-settlement").settle_transfer(event.data.fetch(:transfer_id))
    end
  end
end
