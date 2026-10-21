# 出金依頼の集約（ストリーム "WithdrawalRequest$<依頼ID>"）。窓口取引（TODO の Q1）:
#
#   requested（受付）→ processed（行員が出金した）/ rejected（行員が断った）/ cancelled（利用者が取り消した）
#
# お金の動きは口座側の MoneyWithdrawn（data に request_id）が持ち、こちらは依頼がいまどうなっているかだけ。
# 処理と取消（または二重の処理）がぶつかったら、このストリームの expected_version で後から来た方が負ける
module Banking
  class WithdrawalRequest
    include AggregateRoot

    attr_reader :id, :account_number, :amount, :memo, :status

    def initialize(id)
      @id = id
      @status = :new
    end

    def self.stream_name(id) = "WithdrawalRequest$#{id}"

    def request(account_number:, amount:, memo: nil)
      raise InvalidState, "出金依頼 #{id} はすでに受け付けています" unless status == :new

      apply Events::WithdrawalRequested.new(data: { request_id: id, account_number:, amount:, memo: })
    end

    # 行員が出金した（MoneyWithdrawn と同じトランザクションで書く）
    def process!(withdrawal_event_id:)
      ensure_requested!("処理できません")
      apply Events::WithdrawalRequestProcessed.new(
        data: { request_id: id, account_number:, amount:, withdrawal_event_id: }
      )
    end

    # 行員が断った。理由は必須
    def reject!(reason:)
      ensure_requested!("断れません")
      raise ArgumentError, "断る理由を入れてください" if reason.blank?

      apply Events::WithdrawalRequestRejected.new(data: { request_id: id, account_number:, reason: })
    end

    # 利用者が取り消した（行員が処理する前だけ）
    def cancel!
      ensure_requested!("取り消せません")
      apply Events::WithdrawalRequestCancelled.new(data: { request_id: id, account_number: })
    end

    def requested? = status == :requested

    on Events::WithdrawalRequested do |event|
      @account_number = event.data.fetch(:account_number)
      @amount = event.data.fetch(:amount)
      @memo = event.data[:memo]
      @status = :requested
    end

    on Events::WithdrawalRequestProcessed do |_event|
      @status = :processed
    end

    on Events::WithdrawalRequestRejected do |_event|
      @status = :rejected
    end

    on Events::WithdrawalRequestCancelled do |_event|
      @status = :cancelled
    end

    # 口座側の MoneyWithdrawn もこのストリームにリンクしている（状態には関係ない）
    on Events::MoneyWithdrawn do |_event|
    end

    private

    def ensure_requested!(verb)
      return if requested?
      raise NotFound, "出金依頼 #{id} はありません" if status == :new

      label = ::WithdrawalRequest::STATUS_LABELS.fetch(status.to_s, status.to_s)
      raise InvalidState, "出金依頼は#{label}なので#{verb}"
    end
  end
end
