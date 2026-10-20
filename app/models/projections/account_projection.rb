# イベント → 読み取りモデル（accounts / ledger_entries）。
# publish と同じトランザクションで同期的に呼ばれる。
#
# 読み取りモデルはいつでも捨てて作り直せる（bin/rails churu:rebuild_projections）。
# なので、ここではイベントに書いてあること以外の判断をしない。
module Projections
  class AccountProjection
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
      when Banking::Events::MoneyDeposited
        book(event, kind: "deposit", delta: event.data.fetch(:amount))
      when Banking::Events::MoneyWithdrawn
        book(event, kind: "withdrawal", delta: -event.data.fetch(:amount))
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

    def book(event, kind:, delta:)
      account = ::Account.lock.find_by!(number: number(event))
      account.update!(balance: account.balance + delta)
      LedgerEntry.create!(
        account_number: account.number,
        event_id: event.event_id,
        kind: kind,
        amount: delta,
        balance_after: account.balance,
        memo: event.data[:memo],
        booked_at: event.timestamp,
        value_date: event.valid_at.in_time_zone.to_date,
        actor: event.metadata[:actor]
      )
    end
  end
end
