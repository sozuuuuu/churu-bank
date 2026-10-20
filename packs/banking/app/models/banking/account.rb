# 口座の集約。ストリーム "Account$<口座番号>" のイベントから状態を組み立て、
# 業務ルールを満たしたときだけ新しいイベントを apply する。
#
# 残高はこの集約の中だけで計算する（読み取りモデルの残高は信用しない）。
# 同時に2つの出金が来ても、ストリームの expected_version で後から来た方が失敗するので、
# 残高がマイナスになることはない。
module Banking
  class Account
    include AggregateRoot

    # 日割りの利息は「年利 ÷ 365」（うるう年も 365 で割る）
    DAYS_IN_YEAR = 365

    attr_reader :number, :holder_name, :status, :balance, :interest_carry

    def initialize(number)
      @number = number
      @status = :unopened
      @balance = 0
      @reversible = {}        # 取り消せる取引: event_id => [取消イベントのクラス, 金額]
      @reversed = Set.new     # 取り消し済みの event_id
      @reversals = Set.new    # 取消イベント自身の event_id（取消の取消はできない）
      @interest_dates = Set.new
      @interest_carry = Rational(0)
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

    # 振込の組戻しで、振込先から引き戻す。振込先が使ってしまっていたら残高不足で失敗する。
    # 銀行側の訂正なので凍結中でも受け付ける（解約済みは不可）
    def reverse_transfer_credit(transfer_id:, amount:, from:, reason:)
      ensure_not_closed!
      if amount > balance
        raise InsufficientFunds, "振込先の残高が足りないので組戻しできません（残高 #{balance} / 振込 #{amount}）"
      end

      apply Events::TransferCreditReversed.new(
        data: { account_number: number, transfer_id:, amount:, counterparty: from, reason: }
      )
    end

    # 入金・出金の取消（逆仕訳）。元のイベントは残したまま、逆向きのイベントで相殺する。
    # - 取り消せるのは入金・出金だけ。振込は Bank#reverse_transfer（組戻し）で戻す
    # - 二重取消・取消の取消はできない
    # - 銀行側の訂正なので凍結中でも受け付ける（解約済みは不可）
    # - 入金の取消で残高がマイナスになるときは残高不足で失敗する
    # - 起算日は取消した時点（過去の時点残高は書き換えない）
    def reverse(event_id, reason:)
      ensure_not_closed!
      raise ArgumentError, "取消の理由を入れてください" if reason.blank?
      raise InvalidState, "取消の取引は取り消せません" if @reversals.include?(event_id)
      raise InvalidState, "この取引はすでに取り消されています" if @reversed.include?(event_id)

      reversal, amount = @reversible.fetch(event_id) do
        raise NotFound, "口座 #{number} に取り消せる取引（入金・出金）#{event_id} はありません"
      end
      if reversal == Events::DepositReversed && amount > balance
        raise InsufficientFunds, "残高が足りないので入金を取り消せません（残高 #{balance} / 入金 #{amount}）"
      end

      apply reversal.new(data: { account_number: number, reversed_event_id: event_id, amount:, reason: })
    end

    # 1日分の利息。base_balance は interest_date の日の終わりの残高（起算日基準）。
    #
    # 端数: 「残高 × 年利 ÷ 365 + 前日までの繰り越し」の整数部分を払い、1 未満の端数は
    #       口座ごとに次の日へ繰り越す（切り捨てて消えることはない）。端数は分数のまま持つ。
    # 凍結中: 付ける（凍結は利用者が動かせないだけで、お金は口座にある）。解約済み: 付けない。
    # 同じ日の利息は1回だけ（払った日を集約が覚えている）。
    def pay_interest(date:, base_balance:, annual_rate:)
      ensure_not_closed!
      raise InvalidState, "#{date} の利息は支払い済みです" if interest_paid_on?(date)
      return if base_balance <= 0

      accrued = Rational(base_balance) * Rational(annual_rate) / DAYS_IN_YEAR + interest_carry
      amount = accrued.floor
      apply Events::InterestPaid.new(
        data: { account_number: number, interest_date: date, base_balance:, annual_rate: annual_rate.to_s,
                amount:, carry: (accrued - amount).to_s },
        metadata: { valid_at: (date + 1).in_time_zone.beginning_of_day }
      )
    end

    def interest_paid_on?(date) = @interest_dates.include?(date)

    on Events::AccountOpened do |event|
      @holder_name = event.data.fetch(:holder_name)
      @status = :active
    end

    on Events::MoneyDeposited, Events::MoneyWithdrawn do |event|
      @balance += Events.balance_delta(event)
      @reversible[event.event_id] = [ Events::REVERSALS.fetch(event.class), event.data.fetch(:amount) ]
    end

    on Events::DepositReversed, Events::WithdrawalReversed do |event|
      @balance += Events.balance_delta(event)
      @reversed << event.data.fetch(:reversed_event_id)
      @reversals << event.event_id
    end

    on Events::TransferDebited, Events::TransferCredited, Events::TransferRefunded,
       Events::TransferCreditReversed do |event|
      @balance += Events.balance_delta(event)
    end

    on Events::InterestPaid do |event|
      @balance += Events.balance_delta(event)
      @interest_dates << event.data.fetch(:interest_date).to_date
      @interest_carry = Rational(event.data.fetch(:carry))
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

    def ensure_not_closed!
      case status
      when :unopened then raise NotFound, "口座 #{number} はありません"
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
