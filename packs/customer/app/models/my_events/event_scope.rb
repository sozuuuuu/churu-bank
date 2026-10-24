# 利用者が見てよい出来事: 自分の口座にかかわるものだけ（利用者の「わたしの出来事」/events）。
#   - 自分の口座のストリームの出来事（入金・引き落とし・利息 …）
#   - 自分の口座が振込元か振込先の振込・自分の注文・自分の出金依頼・自分のちゅ〜るローンの出来事
#   - 自分の注文のための在庫の引き当て
# 見せないもの: 他人の口座の出来事（振込の相手の口座への入金など）、二人承認（行員の内部の手続き）、商店そのもの・ほかの人の注文
module MyEvents
  class EventScope
    attr_reader :account_numbers

    def initialize(account_numbers)
      @account_numbers = account_numbers.map(&:to_s).to_set
    end

    def visible?(event)
      kind, id = EventLens::Catalog.home_stream(event).to_s.split("$", 2)
      case kind
      when "Account" then account_numbers.include?(id)
      when "Transfer" then transfer_ids.include?(id)
      when "Order" then order_ids.include?(id)
      when "WithdrawalRequest" then request_ids.include?(id)
      when "Loan" then loan_ids.include?(id)
      when "Product" then order_ids.include?(event.data[:order_id].to_s)
      else false
      end
    end

    # Flow の only: に渡せるように
    def call(event) = visible?(event)

    private

    def transfer_ids = @transfer_ids ||= ::Transfer.involving(account_numbers.to_a).pluck(:transfer_id).to_set
    def order_ids = @order_ids ||= ::ShopOrder.where(buyer_account: account_numbers.to_a).pluck(:order_id).to_set
    def loan_ids = @loan_ids ||= ::Loan.where(account_number: account_numbers.to_a).pluck(:loan_id).to_set
    def request_ids = @request_ids ||= ::WithdrawalRequest.where(account_number: account_numbers.to_a).pluck(:request_id).to_set
  end
end
