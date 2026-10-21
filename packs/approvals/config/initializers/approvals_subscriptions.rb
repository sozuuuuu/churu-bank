# 二人承認のパックのイベント購読。イベントストア本体はルートの config/initializers/event_store.rb が作る
Rails.configuration.to_prepare do
  event_store = Rails.configuration.event_store

  # 同期: 読み取りモデル（approval_requests）の更新
  event_store.subscribe(Approvals::Projection.new, to: Approvals::Events::ALL)
  # 非同期（コミット後）: 行員の画面のライブ更新
  event_store.subscribe(Approvals::RefreshJob, to: Approvals::Events::ALL)
end
