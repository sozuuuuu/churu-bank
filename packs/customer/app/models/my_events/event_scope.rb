# 利用者が見てよい出来事: 自分の口座にかかわるものだけ（利用者の「わたしの出来事」/events）。
#   - 自分の口座のストリームの出来事（入金・引き落とし・利息 …）
#   - 自分の口座が振込元か振込先の振込・自分の注文・自分の出金依頼・自分のちゅ〜るローンの出来事
#   - 自分の注文のための在庫の引き当て
# 見せないもの: 他人の口座の出来事（振込の相手の口座への入金など）、二人承認（行員の内部の手続き）、商店そのもの・ほかの人の注文
module MyEvents
  class EventScope
    attr_reader :account_numbers

    # eager: true … 振込・注文などの ID を口座ぶんまとめて読んでおく（たくさんの出来事を見るとき）
    # eager: false … 1件ずつ DB に聞く（出来事1件だけを見るとき。索引の係・生中継）
    def initialize(account_numbers, eager: true)
      @account_numbers = account_numbers.map(&:to_s).to_set
      @eager = eager
    end

    def visible?(event)
      kind, id = EventLens::Catalog.home_stream(event).to_s.split("$", 2)
      case kind
      when "Account" then account_numbers.include?(id)
      when "Transfer" then mine?(:transfer_ids, ::Transfer.involving(accounts), :transfer_id, id)
      when "Order" then mine?(:order_ids, ::ShopOrder.where(buyer_account: accounts), :order_id, id)
      when "WithdrawalRequest" then mine?(:request_ids, ::WithdrawalRequest.where(account_number: accounts), :request_id, id)
      when "Loan" then mine?(:loan_ids, ::Loan.where(account_number: accounts), :loan_id, id)
      when "Product" then mine?(:order_ids, ::ShopOrder.where(buyer_account: accounts), :order_id, event.data[:order_id].to_s)
      else false
      end
    end

    # Flow の only: に渡せるように
    def call(event) = visible?(event)

    private

    def accounts = account_numbers.to_a

    def mine?(set, scope, column, id) = @eager ? send(set).include?(id) : scope.exists?(column => id)

    def transfer_ids = @transfer_ids ||= ::Transfer.involving(account_numbers.to_a).pluck(:transfer_id).to_set
    def order_ids = @order_ids ||= ::ShopOrder.where(buyer_account: account_numbers.to_a).pluck(:order_id).to_set
    def loan_ids = @loan_ids ||= ::Loan.where(account_number: account_numbers.to_a).pluck(:loan_id).to_set
    def request_ids = @request_ids ||= ::WithdrawalRequest.where(account_number: account_numbers.to_a).pluck(:request_id).to_set
  end
end
