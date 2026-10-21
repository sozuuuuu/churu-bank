# 二人承認の唯一の入口（行員の画面が使う）。取消・組戻し・凍結の解除を「申請 → 別の行員が承認 → 実行」にする。
#
#   desk = Approvals::Desk.new(actor: "staff:1")
#   desk.request_reversal("0000001", event_id, reason: "金額まちがい")     # 入出金の取消を申請
#   desk.request_transfer_reversal(transfer_id, reason: "振込先まちがい")  # 振込の組戻しを申請
#   desk.request_unfreeze("0000001", reason: "本人確認できた")            # 凍結の解除を申請
#   Approvals::Desk.new(actor: "staff:2").approve(approval_id)            # 別の行員が承認 → その場で実行
#   Approvals::Desk.new(actor: "staff:2").reject(approval_id, reason: "証跡がない")
#   desk.withdraw(approval_id)                                            # 申請した本人が取り下げる
#
# - 申請のときに銀行でドライランして、いまできる操作かを確かめる（できなければ申請もできない）。Submitted#outcome がその試算
# - 承認は、銀行の操作（Banking::Bank に Approval を渡す）と ApprovalGranted / ApprovalExecuted を1つのトランザクションで書く。
#   銀行で失敗したら（その間に残高が減った等）全部戻り、申請は承認待ちのまま（却下するか、直してから承認し直す）
# - 同じ対象（同じ通帳の行・振込・口座の解除）の承認待ちは1つだけ
module Approvals
  class Desk
    Submitted = Data.define(:approval_id, :outcome)

    def initialize(actor:, event_store: Rails.configuration.event_store)
      @actor = actor
      @event_store = event_store
      @repository = AggregateRoot::Repository.new(event_store)
    end

    def request_reversal(number, event_id, reason:, dry_run: false)
      entry = ::LedgerEntry.find_by(account_number: number, event_id:)
      raise Banking::NotFound, "口座 #{number} に取引 #{event_id} はありません" unless entry

      summary = "#{entry.account.holder_name}（#{number}）の#{entry.kind_label} #{entry.amount.abs} ちゅ〜る" \
                "（#{entry.booked_at.strftime('%Y/%m/%d %H:%M')}#{" #{entry.memo}" if entry.memo.present?}）"
      submit("reversal", { account_number: number, ledger_event_id: event_id }, reason:, summary:, dry_run:)
    end

    def request_transfer_reversal(transfer_id, reason:, dry_run: false)
      transfer = ::Transfer.includes(:source, :destination).find_by(transfer_id:)
      raise Banking::NotFound, "振込 #{transfer_id} はありません" unless transfer

      summary = "#{transfer.source.holder_name}（#{transfer.from_account}）→ #{transfer.destination.holder_name}" \
                "（#{transfer.to_account}）の振込 #{transfer.amount} ちゅ〜る（#{transfer.requested_at.strftime('%Y/%m/%d %H:%M')}）"
      submit("transfer_reversal", { account_number: transfer.from_account, transfer_id: }, reason:, summary:, dry_run:)
    end

    def request_unfreeze(number, reason:, dry_run: false)
      account = ::Account.find_by(number:)
      raise Banking::NotFound, "口座 #{number} はありません" unless account

      summary = "#{account.holder_name}（#{number}）の口座の凍結を解除"
      submit("unfreeze", { account_number: number }, reason:, summary:, dry_run:)
    end

    # 申請者とは別の行員が承認して、その場で実行する。返すのは銀行の Outcome（dry_run なら試算だけ）
    def approve(approval_id, dry_run: false)
      request = load_existing(approval_id)
      approval = Banking::Bank::Approval.new(id: approval_id, requested_by: request.requested_by)
      request.grant!(approved_by: @actor) # 状態と「本人でないこと」を先に確かめる
      return execute(request, approval:, dry_run: true) if dry_run

      ActiveRecord::Base.transaction do
        outcome = execute(request, approval:, dry_run: false)
        request.executed!(event_ids: outcome.events.map(&:event_id))
        store(request) do
          outcome.events.each { |event| @event_store.link(event.event_id, stream_name: Request.stream_name(approval_id)) }
        end
        outcome
      end
    end

    # 申請者とは別の行員が却下する（理由は必須）。銀行は何も変わらない
    def reject(approval_id, reason:, dry_run: false)
      request = load_existing(approval_id)
      request.reject!(rejected_by: @actor, reason: reason.to_s.strip)
      store(request) unless dry_run
      request
    end

    # 申請した本人が取り下げる
    def withdraw(approval_id)
      request = load_existing(approval_id)
      request.withdraw!(by: @actor)
      store(request)
      request
    end

    # 同じ対象の承認待ちを1つにするためのキー（読み取りモデルの一意インデックス）
    def self.target_key(kind, data)
      case kind
      when "reversal" then "reversal:#{data.fetch(:ledger_event_id)}"
      when "transfer_reversal" then "transfer_reversal:#{data.fetch(:transfer_id)}"
      when "unfreeze" then "unfreeze:#{data.fetch(:account_number)}"
      else raise ArgumentError, "知らない申請の種類です（#{kind}）"
      end
    end

    private

    def bank = Banking::Bank.new(actor: @actor, event_store: @event_store)

    def submit(kind, target, reason:, summary:, dry_run:)
      reason = reason.to_s.strip
      raise ArgumentError, "申請の理由を入れてください" if reason.blank?

      approval_id = SecureRandom.uuid
      request = Request.new(approval_id)
      request.request(kind:, reason:, summary:, requested_by: @actor, **target)
      outcome = execute(request, approval: nil, dry_run: true) # いまできる操作か
      if ::ApprovalRequest.pending.exists?(target_key: self.class.target_key(kind, target))
        raise Banking::InvalidState, "同じ対象の#{::ApprovalRequest::KIND_LABELS.fetch(kind)}がすでに承認待ちです"
      end

      store(request) unless dry_run
      Submitted.new(approval_id:, outcome:)
    rescue ActiveRecord::RecordNotUnique
      raise Banking::InvalidState, "同じ対象の#{::ApprovalRequest::KIND_LABELS.fetch(kind)}がすでに承認待ちです"
    end

    def execute(request, approval:, dry_run:)
      case request.kind
      when "reversal"
        bank.reverse(request.account_number, request.ledger_event_id, reason: request.reason, approval:, dry_run:)
      when "transfer_reversal"
        bank.reverse_transfer(request.transfer_id, reason: request.reason, approval:, dry_run:)
      when "unfreeze"
        bank.unfreeze_account(request.account_number, approval:, dry_run:)
      end
    end

    def load_existing(approval_id)
      request = @repository.load(Request.new(approval_id), Request.stream_name(approval_id))
      raise Banking::NotFound, "申請 #{approval_id} はありません" if request.status == :new

      request
    end

    def store(request)
      ActiveRecord::Base.transaction do
        @event_store.with_metadata(actor: @actor) do
          @repository.store(request, Request.stream_name(request.id))
          yield if block_given?
        end
      end
    rescue RubyEventStore::WrongExpectedEventVersion
      raise Banking::ConcurrentModification, "申請が同時に更新されました。もう一度やり直してください"
    end
  end
end
