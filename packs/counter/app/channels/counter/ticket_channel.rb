# 利用者が、自分の番号札の動き（前に何人・呼ばれた・終わった）を受け取るチャンネル。
# 購読できるのは、利用者としてつないだ接続で、その札の持ち主だけ（他人の札の id を送っても断る）。
# ブラウザからは何も送らない（受け取るだけ）。流すのは Counter::Broadcasts
module Counter
  class TicketChannel < ActionCable::Channel::Base
    def subscribed
      ticket = current_customer && CounterTicket.active.find_by(id: params[:ticket_id], customer_id: current_customer.id)
      return reject unless ticket

      stream_for ticket
      # つないだ時点の順番をすぐ送る（ページを開いてからつながるまでに列が動いていても合うように）
      if ticket.waiting?
        transmit({ type: "position", number: ticket.number, ahead: ticket.ahead, staff_at_counter: Broadcasts.staff_at_counter? })
      end
    end
  end
end
