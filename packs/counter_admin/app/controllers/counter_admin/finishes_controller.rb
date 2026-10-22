# 「終わる」: チャットを閉じて札を終わりにし、列へ戻る（次の方を呼べる）。利用者の画面には closed が届く
module CounterAdmin
  class FinishesController < ApplicationController
    def create
      ticket = Counter::Desk.finish(params[:ticket_id], current_staff)
      redirect_to counter_admin_queue_path, notice: "#{ticket.number} 番の対応を終えました。"
    end
  end
end
