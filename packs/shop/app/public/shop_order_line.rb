# 読み取りモデル: 注文の明細1行（注文したときの値段で残す）
class ShopOrderLine < ApplicationRecord
  belongs_to :order, class_name: "ShopOrder", primary_key: :order_id, foreign_key: :order_id, inverse_of: :lines

  def subtotal = unit_price * quantity
end
