# 読み取りモデルを作るプロジェクション（同期ハンドラ）
module Projections
  # プロジェクションと、それが受け取るイベント。購読（banking_subscriptions.rb）と作り直し（Rebuild）で共有する
  def self.all
    {
      AccountProjection.new => Banking::Events::ACCOUNT,
      TransferProjection.new => Banking::Events::TRANSFER
    }
  end
end
