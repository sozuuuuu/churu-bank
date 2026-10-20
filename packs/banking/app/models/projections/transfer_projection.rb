# イベント → 読み取りモデル（transfers）。publish と同じトランザクションで同期的に呼ばれる
module Projections
  class TransferProjection
    def call(event)
      case event
      when Banking::Events::TransferRequested
        ::Transfer.create!(
          transfer_id: event.data.fetch(:transfer_id),
          from_account: event.data.fetch(:from_account),
          to_account: event.data.fetch(:to_account),
          amount: event.data.fetch(:amount),
          memo: event.data[:memo],
          status: "requested",
          requested_at: event.timestamp,
          actor: event.metadata[:actor]
        )
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

    def find(event) = ::Transfer.find_by!(transfer_id: event.data.fetch(:transfer_id))
  end
end
