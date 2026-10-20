# 商店パックのイベント購読。イベントストア本体はルートの config/initializers/event_store.rb が作る
Rails.configuration.to_prepare do
  event_store = Rails.configuration.event_store
  events = Shop::Events

  # 同期: 読み取りモデルの更新
  event_store.subscribe(Shop::Projections::ProductProjection.new, to: events::PRODUCT)
  event_store.subscribe(Shop::Projections::OrderProjection.new, to: events::ORDER)

  # 非同期（コミット後に Solid Queue へ）
  # - 銀行の振込が終わったら、商店の支払い・返金なら注文を進める（銀行は商店を知らない）
  event_store.subscribe(Shop::PaymentJob, to: [ Banking::Events::TransferCompleted, Banking::Events::TransferFailed ])
  # - 商店の画面へのライブ更新
  event_store.subscribe(Shop::BroadcastRefreshJob, to: events::ALL)
end
