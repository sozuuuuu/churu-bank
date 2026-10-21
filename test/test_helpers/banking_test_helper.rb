# 銀行まわりのテスト用ヘルパー。出金は「出金依頼 → 行員が処理」でしかできない（窓口取引、TODO の Q1）ので、
# テストの下ごしらえで出金したいときはこれを使う
module BankingTestHelper
  # 依頼を出して、そのまま行員が処理する。処理の Outcome を返す
  def withdraw_at_counter(number, amount, memo: nil, bank: Banking::Bank.new(actor: "test"))
    request_id = bank.request_withdrawal(number, amount, memo:).request_id
    Banking::Bank.new(actor: "staff:test").process_withdrawal(request_id)
  end

  # 二人承認の操作（取消・組戻し・凍結の解除）を、承認つきで直接呼ぶための Approval
  def approval_for_test(requested_by: "staff:requester") = Banking::Bank::Approval.new(id: SecureRandom.uuid, requested_by:)
end

ActiveSupport.on_load(:active_support_test_case) do
  include BankingTestHelper
end
ActiveSupport.on_load(:action_dispatch_integration_test) do
  include BankingTestHelper
end
