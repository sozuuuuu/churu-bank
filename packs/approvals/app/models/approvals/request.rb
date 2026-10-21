# 申請の集約（ストリーム "Approval$<申請ID>"）。状態の移り変わり:
#
#   pending（承認待ち）→ 承認 → executed（実行済み。承認と実行は同じトランザクション）
#                     → rejected（却下）/ withdrawn（取り下げ）
#
# 二重に承認・却下しようとしても、状態とストリームの expected_version で1回分しか通らない
module Approvals
  class Request
    include AggregateRoot

    attr_reader :id, :kind, :account_number, :ledger_event_id, :transfer_id, :reason, :requested_by, :status

    def initialize(id)
      @id = id
      @status = :new
    end

    def self.stream_name(id) = "Approval$#{id}"

    def request(kind:, reason:, summary:, requested_by:, account_number: nil, ledger_event_id: nil, transfer_id: nil)
      raise Banking::InvalidState, "申請 #{id} はすでに受け付けています" unless status == :new

      apply Events::ApprovalRequested.new(
        data: { approval_id: id, kind:, account_number:, ledger_event_id:, transfer_id:, reason:, summary:, requested_by: }
      )
    end

    def grant!(approved_by:)
      ensure_pending!("承認できません")
      raise Banking::InvalidState, "申請した本人は承認できません（別の行員が承認します）" if approved_by == requested_by

      apply Events::ApprovalGranted.new(data: { approval_id: id, approved_by: })
    end

    def executed!(event_ids:)
      raise Banking::InvalidState, "承認されていないので実行できません" unless status == :granted

      apply Events::ApprovalExecuted.new(data: { approval_id: id, event_ids: })
    end

    def reject!(rejected_by:, reason:)
      ensure_pending!("却下できません")
      if rejected_by == requested_by
        raise Banking::InvalidState, "自分の申請は却下できません（やめるときは取り下げます）"
      end
      raise ArgumentError, "却下の理由を入れてください" if reason.blank?

      apply Events::ApprovalRejected.new(data: { approval_id: id, rejected_by:, reason: })
    end

    def withdraw!(by:)
      ensure_pending!("取り下げられません")
      raise Banking::InvalidState, "取り下げられるのは申請した本人だけです" unless by == requested_by

      apply Events::ApprovalWithdrawn.new(data: { approval_id: id })
    end

    def pending? = status == :pending

    on Events::ApprovalRequested do |event|
      data = event.data
      @kind = data.fetch(:kind)
      @account_number = data[:account_number]
      @ledger_event_id = data[:ledger_event_id]
      @transfer_id = data[:transfer_id]
      @reason = data.fetch(:reason)
      @requested_by = data.fetch(:requested_by)
      @status = :pending
    end

    on Events::ApprovalGranted do |_event|
      @status = :granted
    end

    on Events::ApprovalExecuted do |_event|
      @status = :executed
    end

    on Events::ApprovalRejected do |_event|
      @status = :rejected
    end

    on Events::ApprovalWithdrawn do |_event|
      @status = :withdrawn
    end

    # 実行した銀行のイベントもこのストリームにリンクしている（状態には関係ない）
    on(*Banking::Events::ACCOUNT, *Banking::Events::TRANSFER) do |_event|
    end

    private

    def ensure_pending!(verb)
      return if pending?
      raise Banking::NotFound, "申請 #{id} はありません" if status == :new

      label = ::ApprovalRequest::STATUS_LABELS.fetch(status.to_s, status.to_s)
      raise Banking::InvalidState, "この申請は#{label}なので#{verb}"
    end
  end
end
