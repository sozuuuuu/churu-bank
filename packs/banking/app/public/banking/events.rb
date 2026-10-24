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

    # 窓口での出金（出金依頼を行員が処理したとき）。data: account_number, amount, memo, request_id
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

    # ちゅ〜るローンの貸付で、口座にお金が入った。data: account_number, loan_id, amount, memo
    class LoanDisbursed < RubyEventStore::Event; end

    # ちゅ〜るローンの返済で、口座から引いた。data: account_number, loan_id, amount
    class LoanRepaymentDebited < RubyEventStore::Event; end

    # ---- 振込（ストリーム Transfer$<振込ID>） ----

    # data: transfer_id, from_account, to_account, amount, memo
    class TransferRequested < RubyEventStore::Event; end

    # data: transfer_id
    class TransferCompleted < RubyEventStore::Event; end

    # data: transfer_id, reason
    class TransferFailed < RubyEventStore::Event; end

    # 完了した振込を組戻しした（振込先から引き戻し → 振込元へ払い戻し）。data: transfer_id, reason
    class TransferReversed < RubyEventStore::Event; end

    # ---- 振込の差し止め（予約・保留・取消・差し止め） ----

    # 予約振込を受け付けた（まだ引き落とさない）。
    # data: transfer_id, from_account, to_account, amount, memo, execute_on
    class TransferScheduled < RubyEventStore::Event; end

    # 予約振込の実行日になり、振込元から引き落とした（このあとは TransferRequested のあとと同じ「処理中」）。
    # data: transfer_id
    class TransferStarted < RubyEventStore::Event; end

    # 予約振込を実行しようとしたが、引き落とせなかった（残高不足・凍結など）。お金は動いていない。
    # data: transfer_id, reason
    class ScheduledTransferFailed < RubyEventStore::Event; end

    # 高額なので、行員が通すか差し止めるまで入金しない（引き落としは済んでいる）。data: transfer_id, threshold
    class TransferHeld < RubyEventStore::Event; end

    # 行員が保留を解いた（このあと入金する）。data: transfer_id
    class TransferReleased < RubyEventStore::Event; end

    # 実行前に、利用者が取り消した（Cancelled）/ 行員が差し止めた（Stopped）。
    # 引き落とし済みだったら振込元へ払い戻している（refunded: true、口座側は TransferRefunded）。
    # data: transfer_id, reason, refunded
    class TransferCancelled < RubyEventStore::Event; end
    class TransferStopped < RubyEventStore::Event; end

    # ---- 出金依頼（窓口取引、ストリーム WithdrawalRequest$<依頼ID>） ----

    # 利用者が出金を依頼した（まだお金は動かない）。data: request_id, account_number, amount, memo
    class WithdrawalRequested < RubyEventStore::Event; end

    # 行員が依頼どおりに出金した（口座側は MoneyWithdrawn。data の request_id でつながる）。
    # data: request_id, account_number, amount, withdrawal_event_id
    class WithdrawalRequestProcessed < RubyEventStore::Event; end

    # 行員が依頼を断った。data: request_id, account_number, reason
    class WithdrawalRequestRejected < RubyEventStore::Event; end

    # 利用者が依頼を取り消した（行員が処理する前だけ）。data: request_id, account_number
    class WithdrawalRequestCancelled < RubyEventStore::Event; end

    # ---- ちゅ〜るローン（貸付、ストリーム Loan$<貸付ID>） ----
    # お金の動きは口座側の LoanDisbursed / LoanRepaymentDebited（Loan$<貸付ID> にもリンクする）。こちらは「いくら借りていて、いくら残っているか」

    # 貸した。返す額は principal + fee（手数料 = 利息。借りたときに決まる）。
    # data: loan_id, account_number, principal, fee, total, memo
    class LoanGranted < RubyEventStore::Event; end

    # 返してもらった。data: loan_id, account_number, amount, outstanding（返したあとの残り）
    class LoanRepaid < RubyEventStore::Event; end

    # 全部返し終わった。data: loan_id, account_number
    class LoanSettled < RubyEventStore::Event; end

    ACCOUNT = [
      AccountOpened, MoneyDeposited, MoneyWithdrawn, AccountFrozen, AccountUnfrozen, AccountClosed,
      TransferDebited, TransferCredited, TransferRefunded, TransferCreditReversed,
      DepositReversed, WithdrawalReversed, InterestPaid, LoanDisbursed, LoanRepaymentDebited
    ].freeze
    TRANSFER = [
      TransferRequested, TransferCompleted, TransferFailed, TransferReversed,
      TransferScheduled, TransferStarted, ScheduledTransferFailed, TransferHeld, TransferReleased,
      TransferCancelled, TransferStopped
    ].freeze
    WITHDRAWAL_REQUEST = [
      WithdrawalRequested, WithdrawalRequestProcessed, WithdrawalRequestRejected, WithdrawalRequestCancelled
    ].freeze

    LOAN = [ LoanGranted, LoanRepaid, LoanSettled ].freeze

    # 口座側のイベントのうち、Loan$<貸付ID> にもリンクされるもの
    LOAN_MONEY = [ LoanDisbursed, LoanRepaymentDebited ].freeze

    # 口座側のイベントのうち、Transfer$<振込ID> にもリンクされるもの
    TRANSFER_MONEY = [ TransferDebited, TransferCredited, TransferRefunded, TransferCreditReversed ].freeze

    # 取り消せるイベントと、その取消イベント
    REVERSALS = { MoneyDeposited => DepositReversed, MoneyWithdrawn => WithdrawalReversed }.freeze

    # 口座の残高を動かすイベントなら、その増減を返す（それ以外は nil）
    def self.balance_delta(event)
      case event
      when MoneyDeposited, TransferCredited, TransferRefunded, WithdrawalReversed, InterestPaid, LoanDisbursed
        event.data.fetch(:amount)
      when MoneyWithdrawn, TransferDebited, TransferCreditReversed, DepositReversed, LoanRepaymentDebited
        -event.data.fetch(:amount)
      end
    end
  end
end
