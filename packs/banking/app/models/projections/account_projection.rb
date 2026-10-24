# イベント → 読み取りモデル（accounts / ledger_entries）。
# publish と同じトランザクションで同期的に呼ばれる。
#
# 読み取りモデルはいつでも捨てて作り直せる（bin/rails churu:rebuild_projections）。
# なので、ここではイベントに書いてあること以外の判断をしない。
module Projections
  class AccountProjection
    LEDGER_KINDS = {
      Banking::Events::MoneyDeposited => "deposit",
      Banking::Events::MoneyWithdrawn => "withdrawal",
      Banking::Events::TransferDebited => "transfer_out",
      Banking::Events::TransferCredited => "transfer_in",
      Banking::Events::TransferRefunded => "transfer_refund",
      Banking::Events::TransferCreditReversed => "transfer_reversal",
      Banking::Events::DepositReversed => "deposit_reversal",
      Banking::Events::WithdrawalReversed => "withdrawal_reversal",
      Banking::Events::InterestPaid => "interest",
      Banking::Events::LoanDisbursed => "loan",
      Banking::Events::LoanRepaymentDebited => "loan_repayment"
    }.freeze

    def call(event)
      case event
      when Banking::Events::AccountOpened
        ::Account.create!(
          number: number(event),
          holder_name: event.data.fetch(:holder_name),
          status: "active",
          balance: 0,
          opened_on: event.data.fetch(:opened_on)
        )
      when *LEDGER_KINDS.keys
        book(event)
      when Banking::Events::AccountFrozen
        ::Account.find_by!(number: number(event)).update!(status: "frozen")
      when Banking::Events::AccountUnfrozen
        ::Account.find_by!(number: number(event)).update!(status: "active")
      when Banking::Events::AccountClosed
        ::Account.find_by!(number: number(event)).update!(status: "closed")
      end
    end

    private

    def number(event) = event.data.fetch(:account_number)

    def book(event)
      delta = Banking::Events.balance_delta(event)
      return if delta.zero? # 0 ちゅ〜るの利息（端数を繰り越しただけ）は通帳に載せない

      account = ::Account.lock.find_by!(number: number(event))
      account.update!(balance: account.balance + delta)
      reversal_of = event.data[:reversed_event_id]
      LedgerEntry.create!(
        account_number: account.number,
        event_id: event.event_id,
        kind: LEDGER_KINDS.fetch(event.class),
        amount: delta,
        balance_after: account.balance,
        memo: memo(event),
        counterparty: event.data[:counterparty],
        transfer_id: event.data[:transfer_id],
        reversal_of:,
        booked_at: event.timestamp,
        value_date: event.valid_at.in_time_zone.to_date,
        actor: event.metadata[:actor]
      )
      LedgerEntry.where(event_id: reversal_of).update_all(reversed_by: event.event_id) if reversal_of
    end

    def memo(event)
      case event
      when Banking::Events::InterestPaid
        "#{event.data.fetch(:interest_date).to_date.strftime('%-m/%-d')} 分の利息"
      when Banking::Events::LoanDisbursed
        event.data[:memo].presence || "ちゅ〜るローン"
      when Banking::Events::LoanRepaymentDebited
        "ちゅ〜るローンの返済"
      else
        event.data[:memo] || event.data[:reason]
      end
    end
  end
end
