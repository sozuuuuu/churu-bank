# イベントストアと、イベント → 読み取りモデル（プロジェクション）の購読設定。
#
# - 同期ハンドラ（プロジェクション）は publish と同じトランザクションで動く
# - 非同期ハンドラ（Active Job）は RES の AfterCommitDispatcher により、コミット後に
#   Solid Queue へ積まれる
require "aggregate_root"

Rails.configuration.to_prepare do
  Rails.configuration.event_store = event_store = RailsEventStore::Client.new
  events = Banking::Events

  # 同期: 読み取りモデルの更新
  event_store.subscribe(Projections::AccountProjection.new, to: events::ACCOUNT)
  event_store.subscribe(Projections::TransferProjection.new, to: events::TRANSFER)

  # 非同期（コミット後に Solid Queue へ）
  event_store.subscribe(Transfers::SettleJob, to: [ events::TransferDebited ]) # 振込の後半（入金 or 組戻し）
  event_store.subscribe(BroadcastRefreshJob, to: events::ACCOUNT + events::TRANSFER) # 画面のライブ更新
end
