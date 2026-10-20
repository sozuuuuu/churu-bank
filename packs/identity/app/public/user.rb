# 利用者。admin なら行員（管理画面に入れる）。口座とは AccountOwnership（口座番号）でつながる
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :account_ownerships, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true

  # その口座の持ち主たち
  scope :owning, ->(account_number) { where(id: AccountOwnership.where(account_number:).select(:user_id)) }

  def account_numbers = account_ownerships.order(:account_number).pluck(:account_number)

  def owns_account?(account_number) = account_ownerships.exists?(account_number:)

  def grant_account(account_number) = account_ownerships.find_or_create_by!(account_number:)
end
