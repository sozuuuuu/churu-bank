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
