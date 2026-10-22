# 「次の方」: いちばん前の札を呼んで、そのチャットへ。呼ばれた利用者の画面ではねこが知らせる（Counter::TicketChannel の called）
module CounterAdmin
  class CallsController < ApplicationController
    def create
      ticket = Counter::Desk.call_next(current_staff)
      if ticket
        redirect_to counter_admin_ticket_path(ticket), notice: "#{ticket.number} 番の #{ticket.customer.name} さんを呼びました。"
      else
        redirect_to counter_admin_queue_path, notice: "お待ちの方はいません。"
      end
    end
  end
end
