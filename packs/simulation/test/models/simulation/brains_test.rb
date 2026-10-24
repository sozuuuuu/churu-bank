require "test_helper"

# 住民の頭: 決まりで動く頭（性格の値で確率を変える）と、Haiku の頭の入り口（API は呼ばない）
class Simulation::BrainsTest < ActiveSupport::TestCase
  L = Simulation::Letters
  I = Simulation::Intent
  MENU = [
    Simulation::Memory::MenuItem.new(sku: "churu", name: "ちゅ〜る", price: 30),
    Simulation::Memory::MenuItem.new(sku: "toy", name: "猫じゃらし", price: 120),
    Simulation::Memory::MenuItem.new(sku: "kotatsu", name: "こたつ", price: 1500)
  ].freeze

  def memory(temperament, money: 300, mood: 60, friends: %w[あずき だいふく])
    Simulation::Memory.wake(name: "こむぎ", temperament: Simulation::Temperament.fetch(temperament), friends:, menu: MENU)
                      .with(money:, mood:)
  end

  def tick(time, payday: false) = L::Tick.new(day: 1, time:, payday:)

  def rules(seed = 1) = Simulation::Brains::Rules.new(random: Random.new(seed))

  def decisions(brain, memory, letter, times: 1000) = Array.new(times) { brain.decide(memory, letter) }

  test "給料日の朝は働き、ふつうの朝は何もしない。夜はねむる" do
    Simulation::Temperament.keys.each do |key|
      assert_instance_of I::Work, rules.decide(memory(key), tick(:morning, payday: true))
      assert_nil rules.decide(memory(key), tick(:morning))
      assert_instance_of I::Rest, rules.decide(memory(key), tick(:night))
    end
  end

  test "衝動買いは倹約家よりずっとよく買いものをする" do
    impulsive = decisions(rules, memory(:impulsive), tick(:noon)).count { it.is_a?(I::Buy) }
    frugal = decisions(rules, memory(:frugal), tick(:noon)).count { it.is_a?(I::Buy) }

    assert_operator impulsive, :>, frugal * 3, "衝動買い #{impulsive} 回・倹約家 #{frugal} 回"
    assert_operator frugal, :>, 0
  end

  test "倹約家はいちばん安い物を、使ってよい額の中でだけ買う。衝動買いはときどき額を気にしない" do
    frugal = decisions(rules, memory(:frugal, money: 400), tick(:noon)).grep(I::Buy)
    assert_equal [ "churu" ], frugal.map(&:sku).uniq

    impulsive = decisions(rules, memory(:impulsive, money: 100), tick(:noon)).grep(I::Buy).map(&:sku).uniq
    assert_includes impulsive, "churu"
    assert_includes impulsive, "kotatsu", "1500 は 100 では買えないが、衝動買いは頼んでしまう"
  end

  test "所持金がわからない・使ってよい額がないときは買わない（気分が高いほど出かける）" do
    assert_empty decisions(rules, memory(:impulsive, money: nil), tick(:noon)).grep(I::Buy)
    assert_empty decisions(rules, memory(:frugal, money: 150), tick(:noon)).grep(I::Buy), "倹約家は 150 を残したい"

    happy = decisions(rules, memory(:caring, mood: 100), tick(:noon)).grep(I::Buy).size
    sad = decisions(rules, memory(:caring, mood: 0), tick(:noon)).grep(I::Buy).size
    assert_operator happy, :>, sad
  end

  test "世話焼きは夕方によくおすそわけし、「足りないにゃ」の手紙が来るとたいてい助ける" do
    caring_gifts = decisions(rules, memory(:caring), tick(:evening)).grep(I::Gift)
    frugal_gifts = decisions(rules, memory(:frugal), tick(:evening)).grep(I::Gift)
    assert_operator caring_gifts.size, :>, frugal_gifts.size * 3
    assert caring_gifts.all? { %w[あずき だいふく].include?(it.to) && it.amount.positive? }

    trouble = L::Trouble.new(from: "あずき", amount: 80)
    helps = decisions(rules, memory(:caring), trouble).grep(I::Gift)
    assert_operator helps.size, :>, 800
    assert helps.all? { it.to == "あずき" && it.amount == 50 }, "助けるのは 50 まで"
    assert_empty decisions(rules, memory(:caring, money: 40), trouble).grep(I::Gift), "使ってよい額より多くは助けない"
    assert_empty decisions(rules, memory(:caring), L::Trouble.new(from: "こむぎ", amount: 10)).grep(I::Gift), "自分の手紙"
  end

  test "残高が足りずに断られると、性格の確率でみんなに助けを求める（足りない額を数える）" do
    request = L::WantPurchase.new(from: "こむぎ", sku: "toy", quantity: 1, reply_to: nil)
    refused = L::Reply.new(request:, ok: false, message: "残高が足りません", balance: 70, reason: :insufficient)
    asks = decisions(rules, memory(:impulsive, money: 70), refused).grep(I::AskHelp)

    assert_operator asks.size, :>, 500
    assert_equal [ 50 ], asks.map(&:amount).uniq
    assert_empty decisions(rules, memory(:impulsive), refused.with(reason: :sold_out)).compact
    assert_empty decisions(rules, memory(:impulsive), refused.with(ok: true)).compact
  end

  test "同じ種なら同じように決める" do
    assert_equal decisions(rules(42), memory(:impulsive), tick(:noon), times: 50),
                 decisions(rules(42), memory(:impulsive), tick(:noon), times: 50)
  end

  test "Haiku の頭: 考える係がなければ決まりで動く頭にまかせる（API は呼ばない）" do
    haiku = Simulation::Brains::Haiku.new(random: Random.new(3))
    assert_equal decisions(rules(3), memory(:impulsive), tick(:noon), times: 50),
                 decisions(haiku, memory(:impulsive), tick(:noon), times: 50)
  end

  test "Haiku の頭: ことば（prompt）を作り、答えの JSON を Intent にする。おかしな答えは何もしない" do
    seen = nil
    haiku = Simulation::Brains::Haiku.new(think: ->(prompt) { seen = prompt; %(はい {"do":"buy","sku":"churu","quantity":2}) })
    assert_equal I::Buy.new(sku: "churu", quantity: 2), haiku.decide(memory(:frugal), tick(:noon))
    assert_includes seen, "こむぎ"
    assert_includes seen, "倹約家"
    assert_includes seen, "churu（ちゅ〜る、30 ちゅ〜る）"

    m = memory(:frugal)
    assert_equal I::Gift.new(to: "あずき", amount: 20, memo: "おれい"),
                 haiku.parse(%({"do":"gift","to":"あずき","amount":20,"memo":"おれい"}), m)
    assert_instance_of I::Rest, haiku.parse(%({"do":"rest"}), m)
    assert_nil haiku.parse(%({"do":"buy","sku":"unknown"}), m), "品書きにない"
    assert_nil haiku.parse(%({"do":"gift","to":"オルカ","amount":20}), m), "知り合いでない"
    assert_nil haiku.parse(%({"do":"gift","to":"あずき","amount":"たくさん"}), m)
    assert_nil haiku.parse("わからないにゃ", m)
  end
end
