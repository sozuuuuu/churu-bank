# ちゅーる銀行で起きる出来事。金額はすべて整数（単位: ちゅ〜る）。
#
# 入出金の「起算日」は RES の valid_at（metadata[:valid_at]）で持つ。
# 記帳日は RES が自動で付ける timestamp。
module Banking
  module Events
    # ---- 口座（ストリーム Account$<口座番号>） ----

    # data: account_number, holder_name, opened_on
    class AccountOpened < RubyEventStore::Event; end

    # data: account_number, amount, memo
    class MoneyDeposited < RubyEventStore::Event; end

    # data: account_number, amount, memo
    class MoneyWithdrawn < RubyEventStore::Event; end

    # data: account_number, reason
    class AccountFrozen < RubyEventStore::Event; end

    # data: account_number
    class AccountUnfrozen < RubyEventStore::Event; end

    # data: account_number
    class AccountClosed < RubyEventStore::Event; end

    # 振込の引き落とし（振込元）。data: account_number, transfer_id, amount, counterparty, memo
    class TransferDebited < RubyEventStore::Event; end

    # 振込の入金（振込先）。data: account_number, transfer_id, amount, counterparty, memo
    class TransferCredited < RubyEventStore::Event; end

    # 振込の組戻し（振込先に入金できず、振込元へ払い戻す）。
    # data: account_number, transfer_id, amount, counterparty, reason
    class TransferRefunded < RubyEventStore::Event; end

    # 完了した振込の組戻しで、振込先から引き戻す（振込元への払い戻しは TransferRefunded）。
    # data: account_number, transfer_id, amount, counterparty, reason
    class TransferCreditReversed < RubyEventStore::Event; end

    # 入金・出金の取消（逆仕訳）。元のイベントは消さず、逆向きのイベントで相殺する。
    # data: account_number, reversed_event_id, amount, reason
    class DepositReversed < RubyEventStore::Event; end
    class WithdrawalReversed < RubyEventStore::Event; end

    # 日次の利息。interest_date の日の終わりの残高（起算日基準）に対する1日分。
    # amount は払った整数部分（0 のこともある）、carry は払いきれずに次の日へ繰り越す端数（"分子/分母"）。
    # 起算日（valid_at）は interest_date の翌日の始まり。
    # data: account_number, interest_date, base_balance, annual_rate, amount, carry
    class InterestPaid < RubyEventStore::Event; end

    # ---- 振込（ストリーム Transfer$<振込ID>） ----

    # data: transfer_id, from_account, to_account, amount, memo
    class TransferRequested < RubyEventStore::Event; end

    # data: transfer_id
    class TransferCompleted < RubyEventStore::Event; end

    # data: transfer_id, reason
    class TransferFailed < RubyEventStore::Event; end

    # 完了した振込を組戻しした（振込先から引き戻し → 振込元へ払い戻し）。data: transfer_id, reason
    class TransferReversed < RubyEventStore::Event; end

    ACCOUNT = [
      AccountOpened, MoneyDeposited, MoneyWithdrawn, AccountFrozen, AccountUnfrozen, AccountClosed,
      TransferDebited, TransferCredited, TransferRefunded, TransferCreditReversed,
      DepositReversed, WithdrawalReversed, InterestPaid
    ].freeze
    TRANSFER = [ TransferRequested, TransferCompleted, TransferFailed, TransferReversed ].freeze

    # 口座側のイベントのうち、Transfer$<振込ID> にもリンクされるもの
    TRANSFER_MONEY = [ TransferDebited, TransferCredited, TransferRefunded, TransferCreditReversed ].freeze

    # 取り消せるイベントと、その取消イベント
    REVERSALS = { MoneyDeposited => DepositReversed, MoneyWithdrawn => WithdrawalReversed }.freeze

    # 口座の残高を動かすイベントなら、その増減を返す（それ以外は nil）
    def self.balance_delta(event)
      case event
      when MoneyDeposited, TransferCredited, TransferRefunded, WithdrawalReversed, InterestPaid
        event.data.fetch(:amount)
      when MoneyWithdrawn, TransferDebited, TransferCreditReversed, DepositReversed
        -event.data.fetch(:amount)
      end
    end
  end
end
