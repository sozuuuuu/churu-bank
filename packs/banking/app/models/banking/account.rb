# 口座の集約。ストリーム "Account$<口座番号>" のイベントから状態を組み立て、
# 業務ルールを満たしたときだけ新しいイベントを apply する。
#
# 残高はこの集約の中だけで計算する（読み取りモデルの残高は信用しない）。
# 同時に2つの出金が来ても、ストリームの expected_version で後から来た方が失敗するので、
# 残高がマイナスになることはない。
module Banking
  class Account
    include AggregateRoot

    attr_reader :number, :holder_name, :status, :balance

    def initialize(number)
      @number = number
      @status = :unopened
      @balance = 0
    end

    def self.stream_name(number) = "Account$#{number}"

    def open(holder_name:, opened_on: Date.current)
      raise AlreadyOpened, "口座 #{number} はすでに開設されています" unless status == :unopened
      raise ArgumentError, "名義を入れてください" if holder_name.blank?

      apply Events::AccountOpened.new(
        data: { account_number: number, holder_name: holder_name, opened_on: opened_on }
      )
    end

    def deposit(amount, memo: nil, value_date: nil)
      ensure_active!
      ensure_positive!(amount)

      apply Events::MoneyDeposited.new(
        data: { account_number: number, amount: amount, memo: memo },
        metadata: value_date_metadata(value_date)
      )
    end

    def withdraw(amount, memo: nil, value_date: nil)
      ensure_active!
      ensure_positive!(amount)
      if amount > balance
        raise InsufficientFunds, "残高不足です（残高 #{balance} / 出金 #{amount}）"
      end

      apply Events::MoneyWithdrawn.new(
        data: { account_number: number, amount: amount, memo: memo },
        metadata: value_date_metadata(value_date)
      )
    end

    # 振込の引き落とし。出金と同じく、残高不足ならその場で失敗する
    def debit_for_transfer(transfer_id:, amount:, to:, memo: nil)
      ensure_active!
      ensure_positive!(amount)
      raise ArgumentError, "自分の口座には振り込めません" if to == number
      if amount > balance
        raise InsufficientFunds, "残高不足です（残高 #{balance} / 振込 #{amount}）"
      end

      apply Events::TransferDebited.new(
        data: { account_number: number, transfer_id:, amount:, counterparty: to, memo: }
      )
    end

    # 振込の入金。振込先が凍結中・解約済みなら InvalidState（→ 組戻しになる）
    def credit_transfer(transfer_id:, amount:, from:, memo: nil)
      ensure_active!
      apply Events::TransferCredited.new(
        data: { account_number: number, transfer_id:, amount:, counterparty: from, memo: }
      )
    end

    # 組戻し。引き落とし済みのお金を返すだけなので、凍結中でも受け付ける
    def refund_transfer(transfer_id:, amount:, to:, reason:)
      raise NotFound, "口座 #{number} はありません" if status == :unopened

      apply Events::TransferRefunded.new(
        data: { account_number: number, transfer_id:, amount:, counterparty: to, reason: }
      )
    end

    def freeze!(reason:)
      ensure_active!
      apply Events::AccountFrozen.new(data: { account_number: number, reason: reason })
    end

    def unfreeze!
      raise InvalidState, "凍結されていません" unless status == :frozen
      apply Events::AccountUnfrozen.new(data: { account_number: number })
    end

    def close!
      ensure_active!
      raise InvalidState, "残高が #{balance} 残っているので解約できません" unless balance.zero?
      apply Events::AccountClosed.new(data: { account_number: number })
    end

    on Events::AccountOpened do |event|
      @holder_name = event.data.fetch(:holder_name)
      @status = :active
    end

    on Events::MoneyDeposited, Events::MoneyWithdrawn,
       Events::TransferDebited, Events::TransferCredited, Events::TransferRefunded do |event|
      @balance += Events.balance_delta(event)
    end

    on Events::AccountFrozen do |_event|
      @status = :frozen
    end

    on Events::AccountUnfrozen do |_event|
      @status = :active
    end

    on Events::AccountClosed do |_event|
      @status = :closed
    end

    private

    def ensure_active!
      case status
      when :active then nil
      when :unopened then raise NotFound, "口座 #{number} はありません"
      when :frozen then raise InvalidState, "口座 #{number} は凍結されています"
      when :closed then raise InvalidState, "口座 #{number} は解約済みです"
      end
    end

    def ensure_positive!(amount)
      raise ArgumentError, "金額は1以上の整数で入れてください" unless amount.is_a?(Integer) && amount.positive?
    end

    # 起算日は「その日の始まり」として valid_at に入れる。指定がなければ記帳時刻と同じ。
    def value_date_metadata(value_date)
      value_date ? { valid_at: value_date.in_time_zone.beginning_of_day } : {}
    end
  end
end
