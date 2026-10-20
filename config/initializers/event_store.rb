# イベントストア本体。すべてのパック（銀行・商店 …）で1つを共有する。
#
# - 同期ハンドラ（プロジェクション）は publish と同じトランザクションで動く
# - 非同期ハンドラ（Active Job）は RES の AfterCommitDispatcher により、コミット後に
#   Solid Queue へ積まれる
#
# 各パックは自分の config/initializers で、自分のハンドラだけを購読する
# （例: packs/banking/config/initializers/banking_subscriptions.rb）。
# ルートの初期化ファイルが先に読まれ、to_prepare もこの順で動く。
require "aggregate_root"

Rails.configuration.to_prepare do
  Rails.configuration.event_store = event_store = RailsEventStore::Client.new
  events = Banking::Events

  # 画面のライブ更新（画面はルートのパッケージにあるので、ここで購読する）
  event_store.subscribe(BroadcastRefreshJob, to: events::ACCOUNT + events::TRANSFER)
end
