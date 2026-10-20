# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# ---- ちゅ〜る商店（packs/shop）: 商店の口座と商品。何度流しても同じになる ----
shop = Shop::Store.new(actor: "seed")
shop.open_shop
[
  { sku: "churu", name: "ちゅ〜る（まぐろ）", emoji: "🐟", price: 30, stock: 30 },
  { sku: "churu-chicken", name: "ちゅ〜る（とりささみ）", emoji: "🍗", price: 30, stock: 20 },
  { sku: "nekojarashi", name: "猫じゃらし", emoji: "🪶", price: 120, stock: 5 },
  { sku: "tsumetogi", name: "爪とぎ", emoji: "🪵", price: 300, stock: 1 },
  { sku: "kotatsu", name: "ねこ用こたつ", emoji: "🛋️", price: 1500, stock: 0 }
].each do |product|
  next if ShopProduct.exists?(sku: product[:sku])

  shop.register_product(**product.except(:stock))
  shop.restock(product[:sku], product[:stock]) if product[:stock].positive?
end
