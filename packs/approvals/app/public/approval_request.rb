# 読み取りモデル: 二人承認の申請。書き込みは Approvals::Desk → イベント → プロジェクションだけ
class ApprovalRequest < ApplicationRecord
  KIND_LABELS = {
    "reversal" => "入出金の取消", "transfer_reversal" => "振込の組戻し", "unfreeze" => "凍結の解除"
  }.freeze
  STATUS_LABELS = {
    "pending" => "承認待ち", "granted" => "承認済み", "executed" => "実行済み", "rejected" => "却下", "withdrawn" => "取り下げ"
  }.freeze

  scope :pending, -> { where(status: "pending") }
  scope :decided, -> { where.not(status: "pending") }

  def to_param = approval_id

  def kind_label = KIND_LABELS.fetch(kind, kind)
  def status_label = STATUS_LABELS.fetch(status, status)

  def pending? = status == "pending"

  # この行員が承認・却下できるか（画面のボタン用。最終判断は Approvals::Desk）。申請した本人はできない
  def decidable_by?(actor) = pending? && requested_by != actor

  # 取り下げられるか（申請した本人だけ）
  def withdrawable_by?(actor) = pending? && requested_by == actor
end
