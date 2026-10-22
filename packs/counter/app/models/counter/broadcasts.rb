# 整理券とチャットの出来事を、Action Cable のチャンネルに流す（サーバー → ブラウザ）。Counter::Desk と チャンネルが呼ぶ。
# 中身は小さな JSON（HTML にしない）。ブラウザの Stimulus が受け取って画面を変える
#
#   TicketChannel（札ごと、その札の利用者だけ）… position（前に何人）/ called（呼ばれた）/ closed（終わった）
#   ChatChannel（札ごと、その札の利用者と行員）… message / typing / presence（在席）/ closed
#   QueueChannel（行員みんな）               … changed（列が変わった。行員の画面は列を読み直す）
module Counter
  module Broadcasts
    module_function

    # 列が変わった（札を取った・返した・呼んだ・終わった、窓口に行員が来た・帰った）。
    # 待っている札それぞれに「前に何人」を、行員には「変わった」だけを送る
    def queue_changed
      staff_at_counter = staff_at_counter?
      CounterTicket.waiting.each_with_index do |ticket, index|
        TicketChannel.broadcast_to(ticket, { type: "position", number: ticket.number, ahead: index, staff_at_counter: })
      end
      ActionCable.server.broadcast(QueueChannel::STREAM, { type: "changed" })
    end

    def called(ticket)
      TicketChannel.broadcast_to(ticket, { type: "called", number: ticket.number, staff_name: ticket.staff_name })
    end

    def closed(ticket)
      payload = { type: "closed", number: ticket.number, status: ticket.status, by: ticket.closed_by.to_s.split(":").first }
      TicketChannel.broadcast_to(ticket, payload)
      ChatChannel.broadcast_to(ticket, payload)
    end

    def message(message) = ChatChannel.broadcast_to(message.ticket, message.to_broadcast)

    def typing(ticket, role:) = ChatChannel.broadcast_to(ticket, { type: "typing", role: })

    def presence(ticket, role:) = ChatChannel.broadcast_to(ticket, presence_payload(ticket, role))

    def presence_payload(ticket, role)
      names = CounterPresence.in_room(ticket.room).where(role:).distinct.pluck(:name)
      { type: "presence", role:, present: names.any?, names: }
    end

    def staff_at_counter? = CounterPresence.in_room(CounterPresence::LOBBY).exists?
  end
end
