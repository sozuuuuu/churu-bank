# 読み取りモデル: 通帳の1行
class LedgerEntry < ApplicationRecord
  KIND_LABELS = {
    "deposit" => "入金",
    "withdrawal" => "出金",
    "transfer_out" => "振込（送金）",
    "transfer_in" => "振込（受取）",
    "transfer_refund" => "組戻し"
  }.freeze

  belongs_to :account, primary_key: :number, foreign_key: :account_number, inverse_of: false

  def kind_label = KIND_LABELS.fetch(kind, kind)

  # 記帳日と起算日がずれている（あとから過去日付で記帳した）行
  def backdated? = value_date != booked_at.to_date
end
