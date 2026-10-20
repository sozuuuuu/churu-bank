# 読み取りモデル（accounts / ledger_entries / transfers）を空にして、イベントストアの全イベントを
# 書かれた順にプロジェクションへ流し直す（bin/rails churu:rebuild_projections）。
#
# - イベントストアの購読は通さず、プロジェクションを直接呼ぶ。なので非同期ハンドラ
#   （振込の SettleJob や画面の BroadcastRefreshJob）は動かない
# - 全体を1つのトランザクションで行うので、途中で失敗したら元の読み取りモデルのまま
# - Transfer$<id> にリンクされた口座のイベントは、全体を読むときは1回しか出てこない
module Projections
  class Rebuild
    def initialize(event_store: Rails.configuration.event_store)
      @event_store = event_store
    end

    # 流したイベントの数を返す
    def call
      projections = Projections.all
      count = 0
      ActiveRecord::Base.transaction do
        [ LedgerEntry, ::Transfer, ::Account ].each(&:delete_all)
        @event_store.read.each do |event|
          projections.each { |projection, types| projection.call(event) if types.include?(event.class) }
          count += 1
        end
      end
      count
    end
  end
end
