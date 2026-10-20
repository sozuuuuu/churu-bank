# 読み取りモデル: 通帳の1行
class LedgerEntry < ApplicationRecord
  KIND_LABELS = { "deposit" => "入金", "withdrawal" => "出金" }.freeze

  belongs_to :account, primary_key: :number, foreign_key: :account_number, inverse_of: false

  def kind_label = KIND_LABELS.fetch(kind, kind)

  # 記帳日と起算日がずれている（あとから過去日付で記帳した）行
  def backdated? = value_date != booked_at.to_date
end
