# 行員。利用者（Customer）とは別のテーブル・別のログイン。行員が自分でも口座を持つなら、利用者のアカウントを別に作る
class Staff < ApplicationRecord
  has_secure_password
  has_many :sessions, class_name: "StaffSession", dependent: :delete_all

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true

  # だれの操作か（イベントの metadata の actor）。メールアドレスは変わりうるので id で残す
  def actor = "staff:#{id}"
end
