# 読み取りモデル: 振込の一覧と状態。書き込みは Banking::Bank → イベント → プロジェクションだけ
class Transfer < ApplicationRecord
  STATUS_LABELS = { "requested" => "処理中", "completed" => "完了", "failed" => "組戻し" }.freeze

  belongs_to :source, class_name: "Account", primary_key: :number, foreign_key: :from_account,
                      inverse_of: false
  belongs_to :destination, class_name: "Account", primary_key: :number, foreign_key: :to_account,
                           inverse_of: false

  scope :involving, ->(number) { where(from_account: number).or(where(to_account: number)) }

  def to_param = transfer_id

  def status_label = STATUS_LABELS.fetch(status, status)
end
