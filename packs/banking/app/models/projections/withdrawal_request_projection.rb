# イベント → 読み取りモデル（withdrawal_requests）。publish と同じトランザクションで同期的に呼ばれる
module Projections
  class WithdrawalRequestProjection
    def call(event)
      case event
      when Banking::Events::WithdrawalRequested
        ::WithdrawalRequest.create!(
          request_id: event.data.fetch(:request_id), account_number: event.data.fetch(:account_number),
          amount: event.data.fetch(:amount), memo: event.data[:memo], status: "requested",
          requested_at: event.timestamp, requested_by: event.metadata[:actor]
        )
      when Banking::Events::WithdrawalRequestProcessed
        close(event, "processed", withdrawal_event_id: event.data.fetch(:withdrawal_event_id))
      when Banking::Events::WithdrawalRequestRejected
        close(event, "rejected", reject_reason: event.data.fetch(:reason))
      when Banking::Events::WithdrawalRequestCancelled
        close(event, "cancelled")
      end
    end

    private

    def close(event, status, **attributes)
      ::WithdrawalRequest.find_by!(request_id: event.data.fetch(:request_id))
                         .update!(status:, closed_at: event.timestamp, closed_by: event.metadata[:actor], **attributes)
    end
  end
end
