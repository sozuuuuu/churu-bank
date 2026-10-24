# 読み取りモデル: ちゅ〜るローンの貸付1件（正はイベントストアの Loan$<貸付ID>）
class Loan < ApplicationRecord
  STATUS_LABELS = { "open" => "返済中", "settled" => "完済" }.freeze

  scope :open, -> { where(status: "open") }

  # 口座がいま返す額の合計
  def self.owed_by(account_number) = open.where(account_number:).sum(:outstanding)

  def status_label = STATUS_LABELS.fetch(status, status)
end
