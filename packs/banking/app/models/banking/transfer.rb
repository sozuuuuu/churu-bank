# 振込の集約（ストリーム "Transfer$<振込ID>"）。状態は requested → completed / failed、
# completed → reversed（完了後の組戻し）。
#
# お金の動きは口座側のイベント（TransferDebited / Credited / Refunded）が持ち、
# こちらは「その振込がいまどうなっているか」だけを持つ。
module Banking
  class Transfer
    include AggregateRoot

    attr_reader :id, :from_account, :to_account, :amount, :memo, :status

    def initialize(id)
      @id = id
      @status = :new
    end

    def self.stream_name(id) = "Transfer$#{id}"

    def request(from:, to:, amount:, memo: nil)
      raise InvalidState, "振込 #{id} はすでに受け付けています" unless status == :new

      apply Events::TransferRequested.new(
        data: { transfer_id: id, from_account: from, to_account: to, amount:, memo: }
      )
    end

    def complete!
      ensure_requested!
      apply Events::TransferCompleted.new(data: { transfer_id: id })
    end

    def fail!(reason:)
      ensure_requested!
      apply Events::TransferFailed.new(data: { transfer_id: id, reason: })
    end

    # 完了した振込の組戻し。お金の動き（振込先から引き戻し・振込元へ払い戻し）は口座側のイベント
    def reverse!(reason:)
      raise InvalidState, "振込 #{id} は組戻し済みです" if status == :reversed
      raise InvalidState, "完了した振込だけ組戻しできます（いまは #{status}）" unless status == :completed
      raise ArgumentError, "組戻しの理由を入れてください" if reason.blank?

      apply Events::TransferReversed.new(data: { transfer_id: id, reason: })
    end

    def requested? = status == :requested

    on Events::TransferRequested do |event|
      @from_account = event.data.fetch(:from_account)
      @to_account = event.data.fetch(:to_account)
      @amount = event.data.fetch(:amount)
      @memo = event.data[:memo]
      @status = :requested
    end

    on Events::TransferCompleted do |_event|
      @status = :completed
    end

    on Events::TransferFailed do |_event|
      @status = :failed
    end

    on Events::TransferReversed do |_event|
      @status = :reversed
    end

    # 口座側のお金の動きも、このストリームにリンクされている（Bank#link_to_transfer）。
    # 状態には関係ないが、AggregateRoot は知らないイベントで止まるので受け取っておく
    on(*Events::TRANSFER_MONEY) do |_event|
    end

    private

    def ensure_requested!
      raise InvalidState, "振込 #{id} は処理中ではありません（#{status}）" unless requested?
    end
  end
end
