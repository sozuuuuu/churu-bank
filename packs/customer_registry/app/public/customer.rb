# 利用者（口座の持ち主）。行員（Staff）とは別のテーブル。口座とは AccountOwnership（口座番号）でつながる。
# パスワードは利用者のログイン（packs/customer_identity）が authenticate_by で使う
class Customer < ApplicationRecord
  has_secure_password
  has_many :account_ownerships, dependent: :delete_all

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true

  # その口座の持ち主たち
  scope :owning, ->(account_number) { where(id: AccountOwnership.where(account_number:).select(:customer_id)) }

  def account_numbers = account_ownerships.order(:account_number).pluck(:account_number)

  def owns_account?(account_number) = account_ownerships.exists?(account_number:)

  def grant_account(account_number) = account_ownerships.find_or_create_by!(account_number:)

  # だれの操作か（イベントの metadata の actor）。メールアドレスは変わりうるので id で残す
  def actor = "customer:#{id}"
end
