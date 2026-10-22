# イベントビューア（/admin/events）で眺めるためのデモの出来事。bin/rails churu:demo_events で流す（db/seeds.rb のあとで）。
# 振込・組戻し・高額振込の保留・お買いもの（完了と在庫切れの返金）・出金依頼（処理とお断り）・二人承認（取消と凍結の解除）・
# 起算日をさかのぼった入金・利息を、本物の入口（Banking::Bank・Shop::Store・Approvals::Desk）から一通り起こす。
# 流すたびに同じ出来事がもう1組増える（お金が足りなくなったら、その場面は飛ばす）。
#
# 振込の入金や商店の支払いの続きは、ふだんは Solid Queue のジョブが動かす。ここではジョブをその場で動かす（inline）ので、
# 終わったときには続きのイベントまで全部そろっている（correlation_id / causation_id もふだんと同じに付く）
ActiveJob::Base.queue_adapter = :inline

tama, kuro = Staff.order(:id).first(2)
abort "行員が2人いません。先に bin/rails db:seed を流してください" unless tama && kuro

customers = Customer.where(name: %w[オルカ ジンジベル ミケ]).index_by(&:name)
orca, zingiber, mike = customers.values_at("オルカ", "ジンジベル", "ミケ")
abort "利用者（オルカ・ジンジベル・ミケ）がいません。先に bin/rails db:seed を流してください" unless orca && zingiber && mike

account_of = ->(customer) { customer.account_numbers.first }
o, z, m = [ orca, zingiber, mike ].map(&account_of)

as_customer = ->(customer) { Banking::Bank.new(actor: "customer:#{customer.id}") }
as_staff = ->(staff) { Banking::Bank.new(actor: staff.actor) }

def scene(title)
  yield
  puts "  ✓ #{title}"
rescue Banking::Error, Shop::Error, ArgumentError => e
  puts "  - #{title}（飛ばしました: #{e.message}）"
end

puts "デモの出来事を起こします"

scene("窓口で入金（ミケ 1000）") { as_staff.(tama).deposit(m, 1000, memo: "おとしだま") }
scene("起算日を3日さかのぼった入金（オルカ 40。記帳は今日）") do
  as_staff.(kuro).deposit(o, 40, memo: "3日前の持ち込み分", value_date: 3.days.ago.to_date)
end

scene("振込 オルカ → ジンジベル 50（入金まで）") { as_customer.(orca).transfer(o, z, 50, memo: "おやつ代") }

scene("凍結中の口座への振込 → 組戻し（ジンジベル → ミケ 20）") do
  as_staff.(tama).freeze_account(m, reason: "デモ: 不審なログイン")
  as_customer.(zingiber).transfer(z, m, 20, memo: "おかえし")
end
scene("凍結の解除（たまが申請 → くろが承認）") do
  submitted = Approvals::Desk.new(actor: tama.actor).request_unfreeze(m, reason: "本人確認できた")
  Approvals::Desk.new(actor: kuro.actor).approve(submitted.approval_id)
end

scene("高額振込の保留 → 行員が通す（ミケ → オルカ #{Banking::Bank.hold_threshold}）") do
  held = as_customer.(mike).transfer(m, o, Banking::Bank.hold_threshold, memo: "こたつ代のたてかえ")
  as_staff.(kuro).release_transfer(held.transfer_id)
end

store = Shop::Store.new(actor: "customer:#{mike.id}")
scene("お買いもの（ミケ: ちゅ〜る ×2 → 完了）") do
  store.place_order(order_id: SecureRandom.uuid, buyer_account: m, items: { "churu" => 2 })
end
scene("お買いもの（ミケ: 爪とぎ ×2 → 在庫が足りずキャンセル・返金）") do
  store.place_order(order_id: SecureRandom.uuid, buyer_account: m, items: { "tsumetogi" => 2 })
end
scene("お買いもの（オルカ: ねこ用こたつ → 残高が足りず支払いの失敗）") do
  Shop::Store.new(actor: "customer:#{orca.id}").place_order(order_id: SecureRandom.uuid, buyer_account: o,
                                                          items: { "kotatsu" => 1 })
end

scene("出金依頼 → 窓口で出金（オルカ 30）") do
  request_id = as_customer.(orca).request_withdrawal(o, 30, memo: "病院代").request_id
  as_staff.(tama).process_withdrawal(request_id)
end
scene("出金依頼 → お断り（ジンジベル 10）") do
  request_id = as_customer.(zingiber).request_withdrawal(z, 10, memo: "なんとなく").request_id
  as_staff.(kuro).reject_withdrawal(request_id, reason: "ご本人の確認ができませんでした")
end

scene("入金の取消（まちがえて入金 → たまが申請 → くろが承認）") do
  deposit = as_staff.(tama).deposit(z, 100, memo: "（まちがい）")
  event_id = deposit.events.last.event_id
  submitted = Approvals::Desk.new(actor: tama.actor).request_reversal(z, event_id, reason: "金額まちがい")
  Approvals::Desk.new(actor: kuro.actor).approve(submitted.approval_id)
end

scene("昨日の利息") { Banking::Bank.new(actor: "interest").pay_interest(date: Date.yesterday) }

puts "おしまい。/admin/events で見られます"
