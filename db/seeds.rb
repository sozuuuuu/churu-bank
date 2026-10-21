# 開発用のデータ: 行員2人（二人承認で使う）と、利用者とその口座。何度流しても増えない。
# 行員と利用者は別のアカウント（行員は /admin/session、利用者は /session でログイン）。
# パスワードは開発用のテスト値（本番では使わない）
DEV_PASSWORD = "churu-dev-pass"

# [名前, メール]
staffs = [
  [ "窓口のたま", "tama@staff.churu.test" ],
  [ "係長のくろ", "kuro@staff.churu.test" ]
].map do |name, email_address|
  Staff.find_or_create_by!(email_address:) do |staff|
    staff.name = name
    staff.password = DEV_PASSWORD
  end
end

bank = Banking::Bank.new(actor: "seed")

# [名前, メール, 最初の入金]
customers = [
  [ "オルカ", "orca@churu.test", 300 ],
  [ "ジンジベル", "zingiber@churu.test", 150 ],
  [ "ミケ", "mike@churu.test", 500 ]
]

customers.each do |name, email_address, deposit|
  customer = Customer.find_or_create_by!(email_address:) do |c|
    c.name = name
    c.password = DEV_PASSWORD
  end
  next if customer.account_numbers.any?

  number = bank.open_account(holder_name: name).account_number
  customer.grant_account(number)
  bank.deposit(number, deposit, memo: "はじめてのちゅ〜る")
end

puts "seed: 行員 #{staffs.map(&:email_address).join("・")}、利用者 #{customers.size} 人（パスワードは db/seeds.rb）"

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

# ---- 銀行からのお知らせ（packs/notices）。同じタイトルがなければ出す ----
notices = Notices::Board.new(actor: "seed")
[
  { kind: "info", title: "ジンジベルお迎え準備中",
    body: "ちゅーる銀行に、新しいねこ「ジンジベル」がやってきます。\nただいまお迎えの準備中です。窓口で見かけたら、やさしく声をかけてにゃ。" },
  { kind: "request", title: "住所変更のお届けをお願いします", important: true,
    body: "お引っ越しをされた方は、窓口（行員）まで新しいご住所をお届けください。\nお届けがないと、大事なお手紙（ちゅ〜るの試供品など）が届きません。" },
  { kind: "maintenance", title: "メンテナンスのお知らせ", ends_at: 7.days.from_now.end_of_day,
    body: "毎日 0:05 ごろ、利息の計算のため、ほんの少しのあいだ残高の表示が遅れることがあります。\nお昼寝しながらお待ちください。" }
].each do |notice|
  notices.post(**notice) unless Notice.exists?(title: notice[:title])
end
