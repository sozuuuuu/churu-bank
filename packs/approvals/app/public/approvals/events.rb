# 二人承認の出来事（ストリーム Approval$<申請ID>）。だれがしたかは metadata の actor（staff:<id>）
module Approvals
  module Events
    # 行員が申請した。kind は reversal（入出金の取消）/ transfer_reversal（振込の組戻し）/ unfreeze（凍結の解除）。
    # 対象は kind ごとに account_number・ledger_event_id（取り消す通帳の行）・transfer_id。summary は画面に出す説明。
    # data: approval_id, kind, account_number, ledger_event_id, transfer_id, reason, summary, requested_by
    class ApprovalRequested < RubyEventStore::Event; end

    # 申請者とは別の行員が承認した（同じトランザクションで ApprovalExecuted と銀行のイベントも書く）。
    # data: approval_id, approved_by
    class ApprovalGranted < RubyEventStore::Event; end

    # 承認した操作を銀行で実行した。event_ids は銀行のイベント（Approval$ にもリンクしてある）。
    # data: approval_id, event_ids
    class ApprovalExecuted < RubyEventStore::Event; end

    # 申請者とは別の行員が却下した。data: approval_id, rejected_by, reason
    class ApprovalRejected < RubyEventStore::Event; end

    # 申請した本人が取り下げた。data: approval_id
    class ApprovalWithdrawn < RubyEventStore::Event; end

    ALL = [ ApprovalRequested, ApprovalGranted, ApprovalExecuted, ApprovalRejected, ApprovalWithdrawn ].freeze
  end
end
