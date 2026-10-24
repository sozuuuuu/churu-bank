# イベント → 読み取りモデル（loans）。publish と同じトランザクションで同期的に呼ばれる
module Projections
  class LoanProjection
    def call(event)
      data = event.data
      case event
      when Banking::Events::LoanGranted
        ::Loan.create!(loan_id: data.fetch(:loan_id), account_number: data.fetch(:account_number),
                       principal: data.fetch(:principal), fee: data.fetch(:fee), outstanding: data.fetch(:total),
                       status: "open", memo: data[:memo], granted_at: event.timestamp)
      when Banking::Events::LoanRepaid
        ::Loan.find_by!(loan_id: data.fetch(:loan_id)).update!(outstanding: data.fetch(:outstanding))
      when Banking::Events::LoanSettled
        ::Loan.find_by!(loan_id: data.fetch(:loan_id)).update!(status: "settled", settled_at: event.timestamp)
      end
    end
  end
end
