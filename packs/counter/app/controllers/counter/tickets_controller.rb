# 利用者の窓口（/counter）: 番号札を取る・返す。呼ばれたら同じページがチャットになる（Turbo Frame "counter_ticket" の中身が変わる）。
# 利用者としてのログインが必要（packs/customer_identity）。見られるのは自分の札だけ
module Counter
  class TicketsController < ::ApplicationController
    include CustomerAuthentication
    helper Ui::FormatHelper
    helper Ui::ThemeHelper # アイコン・ねこ・セリフ窓（layouts/cat が使う）

    layout "counter/customer"

    def show
      @ticket = CounterTicket.active.find_by(customer: current_customer)
      # 終わったばかりなら、最後のやりとりを見せる
      @last_ticket = CounterTicket.closed.where(customer: current_customer).where(closed_at: 1.hour.ago..).first unless @ticket
    end

    def create
      ticket = Desk.take(current_customer)
      redirect_to counter_path, notice: "#{ticket.number} 番の札を取りました。"
    end

    def destroy
      ticket = Desk.give_back(current_customer)
      redirect_to counter_path, notice: ticket ? "#{ticket.number} 番の札を返しました。" : nil
    end
  end
end
