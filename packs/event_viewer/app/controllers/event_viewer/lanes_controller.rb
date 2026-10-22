# レーン図: 振込・注文・出金依頼・二人承認を1つ選ぶと、関係者（口座・振込・商店 …）を横に並べて、出来事を時間の順に矢印で描く
module EventViewer
  class LanesController < ApplicationController
    RECENT = 12

    def index
      @transfers = ::Transfer.includes(:source, :destination).order(requested_at: :desc, id: :desc).limit(RECENT)
      @orders = ::ShopOrder.recent.limit(RECENT)
      @withdrawal_requests = ::WithdrawalRequest.order(id: :desc).limit(RECENT)
      @approvals = ::ApprovalRequest.order(id: :desc).limit(RECENT)
      @stream = params[:stream].presence
      @stream ||= "Transfer$#{@transfers.first.transfer_id}" if @transfers.any?
      return unless @stream&.match?(EventLens::EventIndex::BUSINESS)

      @flow = EventLens::Flow.of_stream(@stream)
    rescue EventLens::Flow::NotFound
      @flow = nil
    end
  end
end
