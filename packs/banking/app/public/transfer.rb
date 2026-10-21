# 読み取りモデル: 振込の一覧と状態。書き込みは Banking::Bank → イベント → プロジェクションだけ
class Transfer < ApplicationRecord
  STATUS_LABELS = {
    "scheduled" => "予約中", "held" => "保留中",
    "requested" => "処理中", "completed" => "完了", "failed" => "組戻し", "reversed" => "組戻し（取消）",
    "unexecuted" => "実行できず", "cancelled" => "取消済み", "stopped" => "差し止め"
  }.freeze

  # 実行前（利用者は取り消せる・行員は差し止められる）の状態
  PENDING_STATUSES = %w[scheduled held].freeze

  belongs_to :source, class_name: "Account", primary_key: :number, foreign_key: :from_account,
                      inverse_of: false
  belongs_to :destination, class_name: "Account", primary_key: :number, foreign_key: :to_account,
                           inverse_of: false

  scope :involving, ->(number) { where(from_account: number).or(where(to_account: number)) }
  scope :pending, -> { where(status: PENDING_STATUSES) }

  def to_param = transfer_id

  def status_label = STATUS_LABELS.fetch(status, status)

  def scheduled? = status == "scheduled"
  def held? = status == "held"

  # 画面で「取り消す」（利用者）・「差し止める」（行員）を出してよいか（最終判断は Banking::Bank）
  def pending? = PENDING_STATUSES.include?(status)

  # 画面で「通す」を出してよいか（最終判断は Banking::Bank#release_transfer）
  def releasable? = held?

  # 画面で「組戻し」ボタンを出してよいか（最終判断は Banking::Bank#reverse_transfer）
  def reversible? = status == "completed"

  # 状態の補足（取消・差し止めの理由、実行できなかった理由など）
  def status_note = cancel_reason || failure_reason
end
