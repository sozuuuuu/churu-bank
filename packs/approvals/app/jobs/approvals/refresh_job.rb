# RES の非同期ハンドラ。申請のイベントがコミットされたら、行員の「承認待ち」の一覧と対象の口座のページに
# Turbo の refresh（morph）を送る（ほかの行員の画面にも、申請・承認・却下がすぐ映る）
module Approvals
  class RefreshJob < ApplicationJob
    prepend RailsEventStore::AsyncHandler

    queue_as :default

    def perform(event)
      Turbo::StreamsChannel.broadcast_refresh_to("approvals")
      number = ::ApprovalRequest.find_by(approval_id: event.data.fetch(:approval_id))&.account_number
      account = number && ::Account.find_by(number:)
      Turbo::StreamsChannel.broadcast_refresh_to(account) if account
    end
  end
end
