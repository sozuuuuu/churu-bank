# イベント → 読み取りモデル（approval_requests）。publish と同じトランザクションで同期的に呼ばれる
module Approvals
  class Projection
    def call(event)
      case event
      when Events::ApprovalRequested
        data = event.data
        ::ApprovalRequest.create!(
          approval_id: data.fetch(:approval_id), kind: data.fetch(:kind), account_number: data[:account_number],
          ledger_event_id: data[:ledger_event_id], transfer_id: data[:transfer_id], reason: data.fetch(:reason),
          summary: data.fetch(:summary), requested_by: data.fetch(:requested_by), requested_at: event.timestamp,
          target_key: Desk.target_key(data.fetch(:kind), data), status: "pending"
        )
      when Events::ApprovalGranted
        find(event).update!(status: "granted", decided_by: event.data.fetch(:approved_by), decided_at: event.timestamp)
      when Events::ApprovalExecuted
        find(event).update!(status: "executed", executed_at: event.timestamp)
      when Events::ApprovalRejected
        find(event).update!(status: "rejected", decided_by: event.data.fetch(:rejected_by), decided_at: event.timestamp,
                            reject_reason: event.data.fetch(:reason))
      when Events::ApprovalWithdrawn
        find(event).update!(status: "withdrawn", decided_by: event.metadata[:actor], decided_at: event.timestamp)
      end
    end

    # 読み取りモデルを空にして、全イベントから作り直す（bin/rails approvals:rebuild_projections）
    def self.rebuild(event_store: Rails.configuration.event_store)
      projection = new
      ActiveRecord::Base.transaction do
        ::ApprovalRequest.delete_all
        event_store.read.of_type(Events::ALL).each { |event| projection.call(event) }
      end
    end

    private

    def find(event) = ::ApprovalRequest.find_by!(approval_id: event.data.fetch(:approval_id))
  end
end
