require "test_helper"

# 住民の頭: 決まりで動く頭（性格の値で確率を変える）と、Haiku の頭の入り口（API は呼ばない）
class Simulation::BrainsTest < ActiveSupport::TestCase
  L = Simulation::Letters
  I = Simulation::Intent
  MENU = [
    Simulation::Memory::MenuItem.new(sku: "churu", name: "ちゅ〜る", price: 30, food: true),
    Simulation::Memory::MenuItem.new(sku: "chicken", name: "ささみ", price: 35, food: true),
    Simulation::Memory::MenuItem.new(sku: "toy", name: "猫じゃらし", price: 120),
    Simulation::Memory::MenuItem.new(sku: "kotatsu", name: "こたつ", price: 1500)
  ].freeze
  PLACES = Simulation::Roster::PLACES

  def memory(temperament, money: 300, mood: 60, friends: %w[あずき だいふく], debts: {}, ate_day: nil)
    Simulation::Memory.wake(name: "こむぎ", temperament: Simulation::Temperament.fetch(temperament), friends:, menu: MENU,
                            places: PLACES)
                      .with(money:, mood:, debts:, ate_day:, day: 1)
  end

  def tick(time, payday: false, rent_day: false) = L::Tick.new(day: 1, time:, payday:, rent_day:)

  def rules(seed = 1) = Simulation::Brains::Rules.new(random: Random.new(seed))

  def decisions(brain, memory, letter, times: 1000) = Array.new(times) { brain.decide(memory, letter) }

  def refused(request, money: 10) = L::Reply.new(request:, ok: false, message: "残高不足です", balance: money, reason: :insufficient)

  def spending(list) = list.count { it.is_a?(I::Splurge) || it.is_a?(I::Buy) }

  test "給料日の朝は働き、家賃の日の朝は家賃を払い、ふつうの朝は何もしない。夜はねむる" do
    Simulation::Temperament.keys.each do |key|
      assert_instance_of I::Work, rules.decide(memory(key), tick(:morning, payday: true))
      assert_instance_of I::PayRent, rules.decide(memory(key), tick(:morning, rent_day: true))
      assert_nil rules.decide(memory(key), tick(:morning))
      assert_instance_of I::Rest, rules.decide(memory(key), tick(:night))
    end
  end

  test "お昼はごはん。倹約家はいちばん安いごはん。食べた日・所持金がわからないときは買わない" do
    assert_equal [ "churu" ], decisions(rules, memory(:frugal), tick(:noon), times: 50).map(&:sku).uniq
    assert_equal %w[chicken churu], decisions(rules, memory(:impulsive), tick(:noon), times: 200).map(&:sku).uniq.sort
    assert_nil rules.decide(memory(:frugal, ate_day: 1), tick(:noon))
    assert_nil rules.decide(memory(:frugal, money: nil), tick(:noon))
  end

  test "夕方、衝動買いは倹約家よりずっと遊び場や買いものに行く" do
    impulsive = spending(decisions(rules, memory(:impulsive), tick(:evening)))
    frugal = spending(decisions(rules, memory(:frugal), tick(:evening)))

    assert_operator impulsive, :>, frugal * 4, "衝動買い #{impulsive} 回・倹約家 #{frugal} 回"
    assert_operator frugal, :>, 0
  end

  test "倹約家は使ってよい額の中でだけ。衝動買いはときどき額を気にせず、こたつや温泉に行こうとする" do
    frugal = decisions(rules, memory(:frugal, money: 400), tick(:evening))
    budget = memory(:frugal, money: 400).budget
    assert frugal.grep(I::Splurge).all? { Simulation::Roster.place(it.place).price <= budget }
    assert frugal.grep(I::Buy).all? { it.sku == "toy" }

    impulsive = decisions(rules, memory(:impulsive, money: 30), tick(:evening))
    assert_includes impulsive.grep(I::Buy).map(&:sku), "kotatsu", "1500 は 30 では買えないが、衝動買いは頼んでしまう"
    assert_includes impulsive.grep(I::Splurge).map(&:place), "onsen"
  end

  test "気分が高いほど出かける" do
    happy = spending(decisions(rules, memory(:caring, mood: 100), tick(:evening)))
    sad = spending(decisions(rules, memory(:caring, mood: 0), tick(:evening)))
    assert_operator happy, :>, sad
  end

  test "世話焼きは夕方によくおすそわけし、「足りないにゃ」が来るとたいてい助ける（貸すことが多い）" do
    caring_gifts = decisions(rules, memory(:caring), tick(:evening)).grep(I::Gift)
    frugal_gifts = decisions(rules, memory(:frugal), tick(:evening)).grep(I::Gift)
    assert_operator caring_gifts.size, :>, frugal_gifts.size * 3
    assert caring_gifts.all? { %w[あずき だいふく].include?(it.to) && it.amount.positive? }

    trouble = L::Trouble.new(from: "あずき", amount: 80)
    helps = decisions(rules, memory(:caring), trouble).compact
    assert_operator helps.size, :>, 800
    assert_operator helps.grep(I::Lend).size, :>, helps.grep(I::Gift).size, "世話焼きは貸すほうが多い"
    assert helps.all? { it.to == "あずき" && it.amount == 50 }, "助けるのは 50 まで"
    assert_empty decisions(rules, memory(:caring, money: 40), trouble).compact, "使ってよい額より多くは助けない"
    assert_empty decisions(rules, memory(:caring), L::Trouble.new(from: "こむぎ", amount: 10)).compact, "自分の手紙"
  end

  test "残高が足りずに断られると、衝動買いは銀行で借り、倹約家はあまり借りない（足りない額を 10 単位で）" do
    toy = L::WantPurchase.new(from: "こむぎ", sku: "toy", quantity: 1, reply_to: nil)
    impulsive = decisions(rules, memory(:impulsive, money: 10), refused(toy)).grep(I::Borrow)
    frugal = decisions(rules, memory(:frugal, money: 10), refused(toy)).grep(I::Borrow)

    assert_operator impulsive.size, :>, 700
    assert_operator frugal.size, :<, 200
    assert_equal [ 110 ], impulsive.map(&:amount).uniq, "120 - 10 = 110"
    assert_empty decisions(rules, memory(:impulsive), refused(toy).with(reason: :sold_out)).compact
    assert_empty decisions(rules, memory(:impulsive), refused(toy).with(ok: true)).compact
  end

  test "家賃・ごはんで断られると、倹約家でも借りやすい。銀行の上限を超えるなら、みんなに助けを求める" do
    rent = L::PayRent.new(from: "こむぎ", day: 1, reply_to: nil)
    frugal = decisions(rules, memory(:frugal, money: 10), refused(rent)).grep(I::Borrow)
    assert_operator frugal.size, :>, 400
    assert_equal [ 50 ], frugal.map(&:amount).uniq

    full = memory(:impulsive, money: 10, debts: { L::BANK => Simulation::Brains::Rules::LOAN_LIMIT - 20 })
    answers = decisions(rules, full, refused(rent)).compact
    assert_empty answers.grep(I::Borrow)
    assert_operator answers.grep(I::AskHelp).size, :>, 300
  end

  test "お給料が入ったら、いちばん多い借金から返す。衝動買いはあまり返さない" do
    salary = L::Reply.new(request: L::AskSalary.new(from: "こむぎ", day: 1, reply_to: nil), ok: true, message: "お給料",
                          balance: 400)
    debts = { "あずき" => 30, L::BANK => 110 }
    frugal = decisions(rules, memory(:frugal, money: 400, debts:), salary).grep(I::Repay)
    impulsive = decisions(rules, memory(:impulsive, money: 400, debts:), salary).grep(I::Repay)

    assert_operator frugal.size, :>, 900
    assert_equal [ [ L::BANK, 110 ] ], frugal.map { [ it.to, it.amount ] }.uniq
    assert_operator impulsive.size, :<, 500
    assert_empty decisions(rules, memory(:frugal, money: 400), salary).compact, "借金がなければ何もしない"
    poor = decisions(rules, memory(:frugal, money: 200, debts:), salary).grep(I::Repay)
    assert_equal [ 50 ], poor.map(&:amount).uniq, "暮らしの分（150）は残す"
  end

  test "督促状が来たら気分が下がり、夕方は暮らしの分を残して銀行へ返す（返せなければ遊ばずにがまん）。返したら督促は消える。審査で断られたら助けを求める" do
    dunned = memory(:impulsive, money: 230, debts: { L::BANK => 110 }).heard(L::Dun.new(from: "係長のくろ", amount: 110))
    assert dunned.dunned
    assert_equal 50, dunned.mood
    living = Simulation::Brains::Rules::LIVING
    assert_equal [ I::Repay.new(to: L::BANK, amount: 230 - living) ], decisions(rules, dunned, tick(:evening), times: 20).uniq
    assert_equal [ nil ], decisions(rules, dunned.with(money: living), tick(:evening), times: 50).uniq, "返せるお金がなければ、遊ばない"

    repay = L::WantRepay.new(from: "こむぎ", to: L::BANK, amount: 80, reply_to: nil)
    paid = dunned.heard(L::Reply.new(request: repay, ok: true, message: "返しました", balance: 0, debts: { L::BANK => 30 }))
    assert_not paid.dunned

    loan = L::WantLoan.new(from: "こむぎ", amount: 60, reply_to: nil)
    rejected = L::Reply.new(request: loan, ok: false, message: "審査で断られました", balance: 0, reason: :loan_rejected)
    asks = decisions(rules, memory(:impulsive, money: 0), rejected).compact
    assert_operator asks.size, :>, 300
    assert_equal [ I::AskHelp.new(amount: 60) ], asks.uniq
  end

  test "同じ種なら同じように決める" do
    assert_equal decisions(rules(42), memory(:impulsive), tick(:evening), times: 50),
                 decisions(rules(42), memory(:impulsive), tick(:evening), times: 50)
  end

  test "記憶: 夕方までにごはんを食べないと気分が下がる。窓口の返事で借金の帳面と食べた日を書きなおす" do
    m = memory(:frugal, mood: 60)
    assert_equal 60 - 2 + Simulation::Memory::HUNGRY, m.heard(tick(:evening)).mood

    eat = L::WantPurchase.new(from: "こむぎ", sku: "churu", quantity: 1, reply_to: nil)
    fed = m.heard(L::Reply.new(request: eat, ok: true, message: "買いました", balance: 270, debts: { L::BANK => 55 }))
    assert fed.ate_today?
    assert_equal({ L::BANK => 55 }, fed.debts)
    assert_equal 60 + 10 - 2, fed.heard(tick(:evening)).mood
    assert_equal 66, m.heard(L::Lent.new(from: "あずき", amount: 30)).mood
  end

  test "Haiku の頭: 考える係がなければ決まりで動く頭にまかせる（API は呼ばない）" do
    haiku = Simulation::Brains::Haiku.new(random: Random.new(3))
    assert_equal decisions(rules(3), memory(:impulsive), tick(:evening), times: 50),
                 decisions(haiku, memory(:impulsive), tick(:evening), times: 50)
  end

  test "Haiku の頭: ことば（prompt）を作り、答えの JSON を Intent にする。おかしな答えは何もしない" do
    seen = nil
    haiku = Simulation::Brains::Haiku.new(think: ->(prompt) { seen = prompt; %(はい {"do":"buy","sku":"toy","quantity":2}) })
    assert_equal I::Buy.new(sku: "toy", quantity: 2), haiku.decide(memory(:frugal), tick(:noon))
    assert_includes seen, "こむぎ"
    assert_includes seen, "倹約家"
    assert_includes seen, "churu（ちゅ〜る、30 ちゅ〜る、ごはん）"
    assert_includes seen, "onsen（ひなたぼっこ温泉、120 ちゅ〜る）"

    m = memory(:frugal, debts: { "あずき" => 30 })
    assert_equal I::Gift.new(to: "あずき", amount: 20, memo: "おれい"),
                 haiku.parse(%({"do":"gift","to":"あずき","amount":20,"memo":"おれい"}), m)
    assert_instance_of I::Rest, haiku.parse(%({"do":"rest"}), m)
    assert_equal I::Eat.new(sku: "churu"), haiku.parse(%({"do":"eat","sku":"churu"}), m)
    assert_equal I::Splurge.new(place: "cat_cafe"), haiku.parse(%({"do":"fun","place":"cat_cafe"}), m)
    assert_equal I::Borrow.new(amount: 50), haiku.parse(%({"do":"borrow","amount":50}), m)
    assert_equal I::Repay.new(to: "あずき", amount: 30), haiku.parse(%({"do":"repay","to":"あずき","amount":30}), m)
    assert_nil haiku.parse(%({"do":"repay","to":"だいふく","amount":30}), m), "借りていない相手"
    assert_nil haiku.parse(%({"do":"eat","sku":"toy"}), m), "ごはんではない"
    assert_nil haiku.parse(%({"do":"buy","sku":"unknown"}), m), "品書きにない"
    assert_nil haiku.parse(%({"do":"gift","to":"オルカ","amount":20}), m), "知り合いでない"
    assert_nil haiku.parse(%({"do":"gift","to":"あずき","amount":"たくさん"}), m)
    assert_nil haiku.parse("わからないにゃ", m)
  end
end
