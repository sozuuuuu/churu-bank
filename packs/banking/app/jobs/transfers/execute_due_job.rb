# 予約振込の実行。config/recurring.yml で1時間ごとに動き、実行日が今日までの予約振込を
# Bank#execute_transfer で引き落とす（このあとはふつうの振込と同じく SettleJob が入金する）。
# 実行日の 0 時ちょうどでなくてよい（その日のうちに動けばよい）ので、止まっていた時間があっても次の回で拾える。
# 何度動いても、同じ予約は1回しか実行しない
module Transfers
  class ExecuteDueJob < ApplicationJob
    queue_as :default

    def perform(date = Date.current.iso8601)
      Banking::Bank.new(actor: "transfer-scheduler").execute_due_transfers(date: Date.iso8601(date))
    end
  end
end
