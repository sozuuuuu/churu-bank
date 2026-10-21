# イベント → 読み取りモデル（transfers）。publish と同じトランザクションで同期的に呼ばれる
module Projections
  class TransferProjection
    def call(event)
      case event
      when Banking::Events::TransferRequested
        create(event, status: "requested")
      when Banking::Events::TransferScheduled
        create(event, status: "scheduled", execute_on: event.data.fetch(:execute_on).to_date)
      when Banking::Events::TransferStarted
        find(event).update!(status: "requested")
      when Banking::Events::ScheduledTransferFailed
        find(event).update!(status: "unexecuted", settled_at: event.timestamp, failure_reason: event.data[:reason])
      when Banking::Events::TransferHeld
        find(event).update!(status: "held", held_at: event.timestamp)
      when Banking::Events::TransferReleased
        find(event).update!(status: "requested", released_at: event.timestamp)
      when Banking::Events::TransferCancelled, Banking::Events::TransferStopped
        find(event).update!(status: event.is_a?(Banking::Events::TransferCancelled) ? "cancelled" : "stopped",
                            cancelled_at: event.timestamp, cancel_reason: event.data[:reason],
                            cancelled_by: event.metadata[:actor])
      when Banking::Events::TransferCompleted
        find(event).update!(status: "completed", settled_at: event.timestamp)
      when Banking::Events::TransferFailed
        find(event).update!(status: "failed", settled_at: event.timestamp,
                            failure_reason: event.data[:reason])
      when Banking::Events::TransferReversed
        find(event).update!(status: "reversed", reversed_at: event.timestamp,
                            reversal_reason: event.data[:reason])
      end
    end

    private

    def create(event, **attributes)
      ::Transfer.create!(
        transfer_id: event.data.fetch(:transfer_id),
        from_account: event.data.fetch(:from_account),
        to_account: event.data.fetch(:to_account),
        amount: event.data.fetch(:amount),
        memo: event.data[:memo],
        requested_at: event.timestamp,
        actor: event.metadata[:actor],
        **attributes
      )
    end

    def find(event) = ::Transfer.find_by!(transfer_id: event.data.fetch(:transfer_id))
  end
end
