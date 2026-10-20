# 注文の集約（ストリーム "Order$<注文ID>"）。注文IDは画面の確認ステップで決めるので、
# 「注文する」が2回送られても2つめは AlreadyPlaced になる（二重注文・二重払いにならない）。
#
#   payment_pending ─支払い完了─▶ paid ─在庫あり─▶ fulfilled
#        │                          └在庫なし─▶ cancelled ─▶ refunding ─▶ refunded / refund_failed
#        └支払えない─▶ payment_failed
#
# お金の動きは銀行の振込が持ち、こちらは「その注文がいまどうなっているか」だけを持つ。
module Shop
  class Order
    include AggregateRoot

    Line = Data.define(:sku, :name, :unit_price, :quantity) do
      def subtotal = unit_price * quantity
    end

    attr_reader :id, :buyer_account, :lines, :total, :status, :payment_transfer_id, :refund_transfer_id

    def initialize(id)
      @id = id
      @status = :new
      @lines = []
    end

    def self.stream_name(id) = "Order$#{id}"

    def place(buyer_account:, lines:)
      raise AlreadyPlaced, "注文 #{id} はすでに受け付けています" unless status == :new
      raise ArgumentError, "購入者の口座を選んでください" if buyer_account.blank?
      raise ArgumentError, "カートが空です" if lines.empty?
      unless lines.all? { it.quantity.is_a?(Integer) && it.quantity.positive? }
        raise ArgumentError, "数は1以上の整数で入れてください"
      end

      apply Events::OrderPlaced.new(
        data: { order_id: id, buyer_account:, lines: lines.map(&:to_h), total: lines.sum(&:subtotal) }
      )
    end

    def request_payment(transfer_id)
      ensure_status!(:placed)
      apply Events::OrderPaymentRequested.new(data: { order_id: id, transfer_id: })
    end

    def mark_paid!
      ensure_status!(:payment_pending)
      apply Events::OrderPaid.new(data: { order_id: id, transfer_id: payment_transfer_id })
    end

    def fail_payment!(reason:)
      ensure_status!(:placed, :payment_pending)
      apply Events::OrderPaymentFailed.new(data: { order_id: id, reason: })
    end

    def fulfill!
      ensure_status!(:paid)
      apply Events::OrderFulfilled.new(data: { order_id: id })
    end

    def cancel!(reason:)
      ensure_status!(:paid)
      apply Events::OrderCancelled.new(data: { order_id: id, reason: })
    end

    def request_refund(transfer_id)
      ensure_status!(:cancelled)
      apply Events::OrderRefundRequested.new(data: { order_id: id, transfer_id: })
    end

    def mark_refunded!
      ensure_status!(:refunding)
      apply Events::OrderRefunded.new(data: { order_id: id, transfer_id: refund_transfer_id })
    end

    def fail_refund!(reason:)
      ensure_status!(:cancelled, :refunding)
      apply Events::OrderRefundFailed.new(data: { order_id: id, reason: })
    end

    def payment_pending? = status == :payment_pending
    def refunding? = status == :refunding

    on Events::OrderPlaced do |event|
      @buyer_account = event.data.fetch(:buyer_account)
      @lines = event.data.fetch(:lines).map { Line.new(**it.to_h.symbolize_keys) }
      @total = event.data.fetch(:total)
      @status = :placed
    end

    on Events::OrderPaymentRequested do |event|
      @payment_transfer_id = event.data.fetch(:transfer_id)
      @status = :payment_pending
    end

    on(Events::OrderPaid) { |_event| @status = :paid }
    on(Events::OrderPaymentFailed) { |_event| @status = :payment_failed }
    on(Events::OrderFulfilled) { |_event| @status = :fulfilled }
    on(Events::OrderCancelled) { |_event| @status = :cancelled }

    on Events::OrderRefundRequested do |event|
      @refund_transfer_id = event.data.fetch(:transfer_id)
      @status = :refunding
    end

    on(Events::OrderRefunded) { |_event| @status = :refunded }
    on(Events::OrderRefundFailed) { |_event| @status = :refund_failed }

    private

    def ensure_status!(*allowed)
      return if allowed.include?(status)

      raise InvalidState, "注文 #{id} はいま #{status} なので、この操作はできません"
    end
  end
end
