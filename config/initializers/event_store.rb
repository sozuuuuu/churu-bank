# イベントストアと、イベント → 読み取りモデル（プロジェクション）の購読設定。
#
# - 同期ハンドラ（プロジェクション）は publish と同じトランザクションで動く
# - 非同期ハンドラ（Active Job）は RES の AfterCommitDispatcher により、コミット後に
#   Solid Queue へ積まれる
require "aggregate_root"

Rails.configuration.to_prepare do
  Rails.configuration.event_store = event_store = RailsEventStore::Client.new

  account_events = [
    Banking::Events::AccountOpened,
    Banking::Events::MoneyDeposited,
    Banking::Events::MoneyWithdrawn,
    Banking::Events::AccountFrozen,
    Banking::Events::AccountUnfrozen,
    Banking::Events::AccountClosed
  ]

  # 同期: 読み取りモデルの更新
  event_store.subscribe(Projections::AccountProjection.new, to: account_events)
  # 非同期（コミット後に Solid Queue へ）: 画面へのライブ更新
  event_store.subscribe(BroadcastAccountRefreshJob, to: account_events)
end
