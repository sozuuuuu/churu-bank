# 読み取りモデル: 商品カタログと在庫数。書き込みは Shop::Store → イベント → プロジェクションだけ
class ShopProduct < ApplicationRecord
  def to_param = sku

  def display_name = [ emoji, name ].compact.join(" ")

  def in_stock? = stock.positive?
end
