# RES の非同期ハンドラ。口座・振込のイベントがコミットされたら Solid Queue に積まれ、
# 関係する画面に Turbo の refresh（morph）を配信する。
#
# broadcasts_refreshes はプロセス内で少し待ってから（debounce）ジョブを積むので、
# bin/rails runner のようにすぐ終わるプロセスから書き込むと配信が消えてしまう。
# こちらはコミット直後に必ずジョブを積むので、どのプロセスから書き込んでも届く。
class BroadcastRefreshJob < ApplicationJob
  prepend RailsEventStore::AsyncHandler

  queue_as :default

  def perform(event)
    account_numbers(event).each do |number|
      Turbo::StreamsChannel.broadcast_refresh_to(Account.find_by(number:)) if Account.exists?(number:)
    end
    Turbo::StreamsChannel.broadcast_refresh_to("accounts")
    Turbo::StreamsChannel.broadcast_refresh_to("transfers") if event.data.key?(:transfer_id)
  end

  private

  def account_numbers(event)
    data = event.data
    numbers = [ data[:account_number], data[:counterparty], data[:from_account], data[:to_account] ]
    if data.key?(:transfer_id) && (transfer = Transfer.find_by(transfer_id: data[:transfer_id]))
      numbers += [ transfer.from_account, transfer.to_account ]
    end
    numbers.compact.uniq
  end
end
