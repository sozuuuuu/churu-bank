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

    # ---- 振込（ストリーム Transfer$<振込ID>） ----

    # data: transfer_id, from_account, to_account, amount, memo
    class TransferRequested < RubyEventStore::Event; end

    # data: transfer_id
    class TransferCompleted < RubyEventStore::Event; end

    # data: transfer_id, reason
    class TransferFailed < RubyEventStore::Event; end

    ACCOUNT = [
      AccountOpened, MoneyDeposited, MoneyWithdrawn, AccountFrozen, AccountUnfrozen, AccountClosed,
      TransferDebited, TransferCredited, TransferRefunded
    ].freeze
    TRANSFER = [ TransferRequested, TransferCompleted, TransferFailed ].freeze

    # 口座の残高を動かすイベントなら、その増減を返す（それ以外は nil）
    def self.balance_delta(event)
      case event
      when MoneyDeposited, TransferCredited, TransferRefunded then event.data.fetch(:amount)
      when MoneyWithdrawn, TransferDebited then -event.data.fetch(:amount)
      end
    end
  end
end
