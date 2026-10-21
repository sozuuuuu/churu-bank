# 窓口（TODO の Q1）: 利用者の出金依頼の一覧。受付中の依頼を「出金する」（処理）か「断る」。
# 行員が依頼なしに出金する入口はない
module Admin
  class WithdrawalRequestsController < ApplicationController
    def index
      @open_requests = WithdrawalRequest.open.includes(:account).order(:requested_at)
      @closed_requests = WithdrawalRequest.where.not(status: "requested").includes(:account)
                                          .order(closed_at: :desc).limit(30)
    end
  end
end
