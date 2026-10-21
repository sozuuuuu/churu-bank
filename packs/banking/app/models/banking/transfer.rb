# 振込の集約（ストリーム "Transfer$<振込ID>"）。状態の移り変わり:
#
#   requested（処理中）→ completed（完了）/ failed（組戻し）、completed → reversed（完了後の組戻し）
#   scheduled（予約中）→ 実行日に引き落として requested / 引き落とせなければ unexecuted（実行できず）
#   requested → held（高額の保留）→ 行員が通すと requested
#   scheduled・held（実行前）→ cancelled（利用者の取消）/ stopped（行員の差し止め）
#
# お金の動きは口座側のイベント（TransferDebited / Credited / Refunded）が持ち、
# こちらは「その振込がいまどうなっているか」と「引き落とし済みか」だけを持つ。
# 取消と実行がぶつかったときは、このストリームの expected_version で後から来た方が負ける。
module Banking
  class Transfer
    include AggregateRoot

    # 実行前（取り消せる・差し止められる）の状態
    PENDING = %i[scheduled held].freeze

    attr_reader :id, :from_account, :to_account, :amount, :memo, :status, :execute_on

    def initialize(id)
      @id = id
      @status = :new
      @debited = false
      @holdable = true
    end

    def self.stream_name(id) = "Transfer$#{id}"

    def request(from:, to:, amount:, memo: nil)
      ensure_new!
      apply Events::TransferRequested.new(
        data: { transfer_id: id, from_account: from, to_account: to, amount:, memo: }
      )
    end

    # 予約振込。execute_on の日に Bank#execute_transfer が引き落とす（それまでお金は動かない）
    def schedule(from:, to:, amount:, execute_on:, memo: nil, holdable: true)
      ensure_new!
      apply Events::TransferScheduled.new(
        data: { transfer_id: id, from_account: from, to_account: to, amount:, memo:, execute_on:, holdable: }
      )
    end

    # 予約振込の実行日に引き落とした
    def start!
      ensure_status!(:scheduled)
      apply Events::TransferStarted.new(data: { transfer_id: id })
    end

    # 予約振込の実行日に引き落とせなかった（お金は動いていない）
    def fail_scheduled!(reason:)
      ensure_status!(:scheduled)
      apply Events::ScheduledTransferFailed.new(data: { transfer_id: id, reason: })
    end

    # 高額なので保留にする（引き落としは済み、入金はまだ）
    def hold!(threshold:)
      ensure_status!(:requested)
      apply Events::TransferHeld.new(data: { transfer_id: id, threshold: })
    end

    # 行員が保留を解く（このあと SettleJob が入金する）
    def release!
      ensure_status!(:held)
      apply Events::TransferReleased.new(data: { transfer_id: id })
    end

    # 実行前の振込を、利用者が取り消す
    def cancel!(reason:)
      ensure_pending!("取り消せません")
      apply Events::TransferCancelled.new(data: { transfer_id: id, reason:, refunded: debited? })
    end

    # 実行前の振込を、行員が差し止める
    def stop!(reason:)
      ensure_pending!("差し止められません")
      raise ArgumentError, "差し止めの理由を入れてください" if reason.blank?

      apply Events::TransferStopped.new(data: { transfer_id: id, reason:, refunded: debited? })
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
    def scheduled? = status == :scheduled
    def pending? = PENDING.include?(status)

    # 振込元から引き落とし済みか（取消・差し止めで払い戻すかどうか）
    def debited? = @debited

    # 高額の保留の対象か（商店の支払いなどは対象外）
    def holdable? = @holdable

    on Events::TransferRequested do |event|
      assign(event.data)
      @status = :requested
      @debited = true
    end

    on Events::TransferScheduled do |event|
      assign(event.data)
      @execute_on = event.data.fetch(:execute_on).to_date
      @holdable = event.data.fetch(:holdable, true)
      @status = :scheduled
    end

    on Events::TransferStarted, Events::TransferReleased do |_event|
      @status = :requested
      @debited = true
    end

    on Events::ScheduledTransferFailed do |_event|
      @status = :unexecuted
    end

    on Events::TransferHeld do |_event|
      @status = :held
    end

    on Events::TransferCancelled do |_event|
      @status = :cancelled
    end

    on Events::TransferStopped do |_event|
      @status = :stopped
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

    def assign(data)
      @from_account = data.fetch(:from_account)
      @to_account = data.fetch(:to_account)
      @amount = data.fetch(:amount)
      @memo = data[:memo]
    end

    def status_label = ::Transfer::STATUS_LABELS.fetch(status.to_s, status.to_s)

    def ensure_new!
      raise InvalidState, "振込 #{id} はすでに受け付けています" unless status == :new
    end

    def ensure_status!(expected)
      raise InvalidState, "振込 #{id} は#{::Transfer::STATUS_LABELS.fetch(expected.to_s)}ではありません（いまは#{status_label}）" unless status == expected
    end

    def ensure_requested!
      raise InvalidState, "振込 #{id} は処理中ではありません（#{status}）" unless requested?
    end

    # 実行が始まった（処理中）・終わった振込は、取り消しも差し止めもできない
    def ensure_pending!(verb)
      return if pending?

      case status
      when :new then raise NotFound, "振込 #{id} はありません"
      when :requested then raise InvalidState, "振込はもう実行が始まっているので#{verb}（いまは#{status_label}）"
      else raise InvalidState, "振込は#{status_label}なので#{verb}"
      end
    end
  end
end
