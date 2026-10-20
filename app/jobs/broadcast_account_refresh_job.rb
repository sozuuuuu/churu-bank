# RES の非同期ハンドラ。口座のイベントがコミットされたら Solid Queue に積まれ、
# その口座の画面と口座一覧に Turbo の refresh（morph）を配信する。
#
# broadcasts_refreshes はプロセス内で少し待ってから（debounce）ジョブを積むので、
# bin/rails runner のようにすぐ終わるプロセスから書き込むと配信が消えてしまう。
# こちらはコミット直後に必ずジョブを積むので、どのプロセスから書き込んでも届く。
class BroadcastAccountRefreshJob < ApplicationJob
  prepend RailsEventStore::AsyncHandler

  queue_as :default

  def perform(event)
    account = Account.find_by(number: event.data.fetch(:account_number))
    return unless account

    account.broadcast_refresh
    Turbo::StreamsChannel.broadcast_refresh_to("accounts")
  end
end
