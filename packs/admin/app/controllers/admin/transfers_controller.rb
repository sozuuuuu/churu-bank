module Admin
  class TransfersController < ApplicationController
    def index
      @transfers = Transfer.includes(:source, :destination).order(requested_at: :desc).limit(100)
      # 組戻しを申請中（二人承認の承認待ち）の振込には「組戻し」を出さない
      @pending_transfer_ids = ApprovalRequest.pending.where(transfer_id: @transfers.map(&:transfer_id)).pluck(:transfer_id).to_set
    end
  end
end
