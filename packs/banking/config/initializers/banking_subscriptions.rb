# 銀行パックのイベント購読。イベントストア本体はルートの config/initializers/event_store.rb が作る
Rails.configuration.to_prepare do
  event_store = Rails.configuration.event_store
  events = Banking::Events

  # 同期: 読み取りモデルの更新
  # （bin/rails churu:rebuild_projections も同じ Projections.all を使う）
  Projections.all.each { |projection, types| event_store.subscribe(projection, to: types) }

  # 非同期（コミット後に Solid Queue へ）: 振込の後半（入金 or 組戻し）
  event_store.subscribe(Transfers::SettleJob, to: [ events::TransferDebited ])
end
