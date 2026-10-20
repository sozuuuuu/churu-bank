# 読み取りモデル: 注文の一覧と状態。書き込みは Shop::Store → イベント → プロジェクションだけ
class ShopOrder < ApplicationRecord
  STATUS_LABELS = {
    "placed" => "受付",
    "payment_pending" => "支払い待ち",
    "paid" => "支払い済み",
    "payment_failed" => "支払い失敗",
    "fulfilled" => "完了",
    "cancelled" => "キャンセル",
    "refunding" => "返金中",
    "refunded" => "返金済み",
    "refund_failed" => "返金失敗（要対応）"
  }.freeze

  # まだ動きがある状態（画面で「処理中」に見せる）
  IN_PROGRESS = %w[placed payment_pending paid cancelled refunding].freeze

  has_many :lines, -> { order(:id) }, class_name: "ShopOrderLine", primary_key: :order_id,
                                      foreign_key: :order_id, inverse_of: :order

  scope :recent, -> { order(placed_at: :desc, id: :desc) }

  def to_param = order_id

  def short_id = order_id.first(8)

  def status_label = STATUS_LABELS.fetch(status, status)

  def in_progress? = IN_PROGRESS.include?(status)
end
