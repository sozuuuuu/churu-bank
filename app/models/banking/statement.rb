# ある日の終わり時点での残高を、イベントストアから直接計算する（読み取りモデルは使わない）。
#
# 「時点」の見方が2通りある:
#   - :as_of … 起算日（valid_at）基準。「本当はその日に何があったか」。あとから過去日付で
#              記帳した入金も、その日の残高に入る
#   - :as_at … 記帳日（timestamp）基準。「その日の時点で銀行が知っていたこと」
module Banking
  class Statement
    Line = Data.define(:event, :delta, :balance)

    def initialize(number, date:, basis: :as_of, event_store: Rails.configuration.event_store)
      @number = number
      @date = date
      @basis = basis
      @event_store = event_store
    end

    attr_reader :date, :basis

    def lines
      @lines ||= begin
        balance = 0
        scope.filter_map do |event|
          delta = case event
          when Events::MoneyDeposited then event.data.fetch(:amount)
          when Events::MoneyWithdrawn then -event.data.fetch(:amount)
          end
          next unless delta

          balance += delta
          Line.new(event:, delta:, balance:)
        end
      end
    end

    def balance = lines.last&.balance || 0

    private

    def scope
      reader = @event_store.read.stream(Account.stream_name(@number))
      reader = @basis == :as_at ? reader.as_at : reader.as_of
      reader.older_than_or_equal(@date.in_time_zone.end_of_day).to_a
    end
  end
end
