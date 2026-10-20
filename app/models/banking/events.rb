# ちゅーる銀行で起きる出来事。金額はすべて整数（単位: ちゅ〜る）。
#
# 入出金の「起算日」は RES の valid_at（metadata[:valid_at]）で持つ。
# 記帳日は RES が自動で付ける timestamp。
module Banking
  module Events
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
  end
end
