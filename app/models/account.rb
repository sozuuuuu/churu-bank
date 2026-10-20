# 読み取りモデル（画面表示用）。書き込みは Banking::Bank → イベント → プロジェクションだけ。
class Account < ApplicationRecord
  STATUS_LABELS = { "active" => "利用中", "frozen" => "凍結中", "closed" => "解約済み" }.freeze

  has_many :ledger_entries, -> { order(:booked_at, :id) },
           primary_key: :number, foreign_key: :account_number, inverse_of: false

  # 画面への配信（Turbo の refresh）は BroadcastRefreshJob が行う

  def to_param = number

  def status_label = STATUS_LABELS.fetch(status, status)

  def active? = status == "active"
end
