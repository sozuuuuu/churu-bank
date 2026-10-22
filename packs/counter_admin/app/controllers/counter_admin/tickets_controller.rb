# その札のチャット。対応中なら Counter::ChatChannel でやりとり（発言できるのは呼んだ行員だけ。ほかの行員は見るだけ）。
# 終わった札は記録として発言を見るだけ。横に、その利用者の受付中の出金依頼（窓口取引 Q1）
module CounterAdmin
  class TicketsController < ApplicationController
    def show
      @ticket = CounterTicket.includes(:customer, :messages).find(params[:id])
      @withdrawal_requests = WithdrawalRequest.open.where(account_number: @ticket.customer.account_numbers)
                                              .includes(:account).order(:requested_at)
      @speakable = @ticket.speakable_by_staff?(current_staff)
    end
  end
end
