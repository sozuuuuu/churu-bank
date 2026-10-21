# 二人承認（TODO の Q2）: 承認待ちの一覧と最近の結果。取消・組戻し・凍結の解除は、ここで別の行員が承認すると実行される。
# 申請した本人には「承認する」「却下する」を出さず、「取り下げる」だけを出す
module Admin
  class ApprovalsController < ApplicationController
    def index
      @pending = ApprovalRequest.pending.order(:requested_at)
      @decided = ApprovalRequest.decided.order(decided_at: :desc).limit(30)
    end
  end
end
