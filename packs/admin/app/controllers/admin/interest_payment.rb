# 利息の手動実行（全口座・1口座）で共通の、日付の受け取りと確認画面の行づくり
module Admin
  module InterestPayment
    # 確認画面の1行。state: :pay（払う）/ :paid（支払い済み）/ :zero（残高 0）/ :closed（解約済み）
    Row = Data.define(:account, :state, :amount, :base_balance, :carry) do
      def pay? = state == :pay
    end

    private

    def parse_interest_date
      Date.iso8601(params[:date]) if params[:date].present?
    rescue Date::Error
      nil
    end

    # 利息はその日の終わりの残高にかかるので、終わった日（昨日まで）だけ
    def interest_date!
      date = parse_interest_date or raise ArgumentError, "日付を選んでください"
      raise ArgumentError, "まだ終わっていない日の利息は払えません（昨日までの日を選んでください）" if date >= Date.current

      date
    end

    # ドライランで、その日にこの口座へいくら払うか（払わないならその理由）
    def interest_row(account, date)
      if (outcome = bank.pay_interest_to(account.number, date:, dry_run: true))
        data = outcome.events.first.data
        Row.new(account:, state: :pay, amount: data.fetch(:amount), base_balance: data.fetch(:base_balance),
                carry: data.fetch(:carry))
      else
        state = if account.status == "closed" then :closed
        elsif bank.load_account(account.number).interest_paid_on?(date) then :paid
        else :zero
        end
        Row.new(account:, state:, amount: 0, base_balance: nil, carry: nil)
      end
    end

    # 確定後のメッセージ。何も払わなかった（支払い済みの日だった）こともはっきり出す
    def interest_notice(outcomes, date)
      day = helpers.jp_date(date)
      if outcomes.empty?
        { alert: "#{day} の利息は支払い済み（または払う口座がありません）なので、何もしませんでした" }
      else
        total = outcomes.sum { it.events.first.data.fetch(:amount) }
        { notice: "#{day} の利息を #{outcomes.size} 口座に払いました（合計 #{helpers.churu(total)}）" }
      end
    end
  end
end
