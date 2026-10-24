# 読み取りモデル: 通帳の1行
class LedgerEntry < ApplicationRecord
  KIND_LABELS = {
    "deposit" => "入金",
    "withdrawal" => "出金",
    "transfer_out" => "振込（送金）",
    "transfer_in" => "振込（受取）",
    "transfer_refund" => "組戻し",
    "transfer_reversal" => "組戻し（引き戻し）",
    "deposit_reversal" => "取消（入金）",
    "withdrawal_reversal" => "取消（出金）",
    "interest" => "利息",
    "loan" => "借入（ちゅ〜るローン）",
    "loan_repayment" => "返済（ちゅ〜るローン）"
  }.freeze

  # Banking::Bank#reverse で取り消せる種類
  REVERSIBLE_KINDS = %w[deposit withdrawal].freeze

  belongs_to :account, primary_key: :number, foreign_key: :account_number, inverse_of: false

  # 取消の行 ↔ 元の行（どちらもイベント ID でつながる）
  belongs_to :original_entry, class_name: "LedgerEntry", primary_key: :event_id, foreign_key: :reversal_of,
                              optional: true, inverse_of: false
  belongs_to :reversal_entry, class_name: "LedgerEntry", primary_key: :event_id, foreign_key: :reversed_by,
                              optional: true, inverse_of: false

  def kind_label = KIND_LABELS.fetch(kind, kind)

  # 記帳日と起算日がずれている（あとから過去日付で記帳した）行
  def backdated? = value_date != booked_at.to_date

  # 取消の行か（元の行は original_entry）
  def reversal? = reversal_of.present?

  # 取り消された行か（取消の行は reversal_entry）
  def reversed? = reversed_by.present?

  # 画面で「取消」ボタンを出してよいか（最終判断は Banking::Bank#reverse）
  def reversible? = REVERSIBLE_KINDS.include?(kind) && !reversed?
end
