# ちゅ〜るローンの集約（ストリーム "Loan$<貸付ID>"）。
#
#   granted（借りた。返す額 = 借りた額 + 手数料）→ repaid（少しずつ返す）… → settled（全部返した）
#
# 手数料（利息）は借りたときに決めて返す額に足す（日ごとには増えない）。返す額より多くは返せない。
# お金の動きは口座側の LoanDisbursed / LoanRepaymentDebited が持ち、こちらはいくら残っているかだけ
module Banking
  class Loan
    include AggregateRoot

    attr_reader :id, :account_number, :principal, :fee, :outstanding, :status

    def initialize(id)
      @id = id
      @status = :new
      @outstanding = 0
    end

    def self.stream_name(id) = "Loan$#{id}"

    def grant(account_number:, principal:, fee:, memo: nil)
      raise InvalidState, "貸付 #{id} はもう貸しています" unless status == :new

      apply Events::LoanGranted.new(data: { loan_id: id, account_number:, principal:, fee:, total: principal + fee, memo: })
    end

    def repay(amount)
      raise NotFound, "貸付 #{id} はありません" if status == :new
      raise InvalidState, "貸付 #{id} はもう全部返してもらっています" if settled?
      unless amount.is_a?(Integer) && amount.between?(1, outstanding)
        raise ArgumentError, "返す額は 1〜#{outstanding} ちゅ〜るで入れてください"
      end

      apply Events::LoanRepaid.new(data: { loan_id: id, account_number:, amount:, outstanding: outstanding - amount })
      apply Events::LoanSettled.new(data: { loan_id: id, account_number: }) if outstanding.zero?
    end

    def open? = status == :open

    def settled? = status == :settled

    on Events::LoanGranted do |event|
      @account_number = event.data.fetch(:account_number)
      @principal = event.data.fetch(:principal)
      @fee = event.data.fetch(:fee)
      @outstanding = event.data.fetch(:total)
      @status = :open
    end

    on Events::LoanRepaid do |event|
      @outstanding = event.data.fetch(:outstanding)
    end

    on Events::LoanSettled do |_event|
      @status = :settled
    end

    # 口座側の入金・引き落としもこのストリームにリンクしている（状態には関係ない）
    on Events::LoanDisbursed, Events::LoanRepaymentDebited do |_event|
    end
  end
end
