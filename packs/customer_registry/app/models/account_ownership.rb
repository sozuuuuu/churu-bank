# 利用者と口座のひも付け。口座番号は銀行パックの Account#number
class AccountOwnership < ApplicationRecord
  belongs_to :customer

  validates :account_number, presence: true, uniqueness: { scope: :customer_id }
end
