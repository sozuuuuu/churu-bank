# 窓口の列: お待ちの札・対応中の札・最近の終わり。「次の方」ボタン。
# 列が変わると Counter::QueueChannel の changed が届き、Stimulus（counter--queue）が Frame "counter_queue" を読み直す
module CounterAdmin
  class QueuesController < ApplicationController
    def show
      @waiting = CounterTicket.waiting.includes(:customer)
      @called = CounterTicket.called.includes(:customer)
      @closed = CounterTicket.closed.includes(:customer).limit(10)
      @my_ticket = @called.find { it.staff_id == current_staff.id }
    end
  end
end
