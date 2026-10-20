# 開発用のデータ: 管理者（行員）1人と、利用者とその口座。何度流しても増えない。
# パスワードは開発用のテスト値（本番では使わない）
DEV_PASSWORD = "churu-dev-pass"

admin = User.find_or_create_by!(email_address: "admin@churu.test") do |user|
  user.name = "行員"
  user.admin = true
  user.password = DEV_PASSWORD
end

bank = Banking::Bank.new(actor: "seed")

# [名前, メール, 最初の入金]
customers = [
  [ "オルカ", "orca@churu.test", 300 ],
  [ "ジンジベル", "zingiber@churu.test", 150 ],
  [ "ミケ", "mike@churu.test", 500 ]
]

customers.each do |name, email_address, deposit|
  user = User.find_or_create_by!(email_address:) do |u|
    u.name = name
    u.password = DEV_PASSWORD
  end
  next if user.account_numbers.any?

  number = bank.open_account(holder_name: name).account_number
  user.grant_account(number)
  bank.deposit(number, deposit, memo: "はじめてのちゅ〜る")
end

puts "seed: 管理者 #{admin.email_address}、利用者 #{customers.size} 人（パスワードは db/seeds.rb）"

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
