# 読み取りモデル: 出金依頼（窓口取引）。書き込みは Banking::Bank → イベント → プロジェクションだけ
class WithdrawalRequest < ApplicationRecord
  STATUS_LABELS = {
    "requested" => "受付中", "processed" => "出金済み", "rejected" => "お断り", "cancelled" => "取消済み"
  }.freeze

  belongs_to :account, primary_key: :number, foreign_key: :account_number, inverse_of: false

  scope :open, -> { where(status: "requested") }

  def to_param = request_id

  def status_label = STATUS_LABELS.fetch(status, status)

  # 画面で「出金する」「断る」（行員）・「取り消す」（利用者）を出してよいか（最終判断は Banking::Bank）
  def open? = status == "requested"
end
