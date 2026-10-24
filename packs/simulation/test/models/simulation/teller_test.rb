require "test_helper"
require_relative "../../simulation_test_helper"

# 窓口役: 住民の手紙を確かめてから、銀行と商店の公開の入口で書く。断ったら返事でわけを伝える
class Simulation::TellerTest < ActiveSupport::TestCase
  include SimulationTestHelper
  include ActiveJob::TestHelper

  L = Simulation::Letters

  setup do
    @komugi = create_resident("こむぎ", deposit: 100)
    @azuki = create_resident("あずき", deposit: 50)
    bank = Banking::Bank.new(actor: "test")
    @employer = bank.open_account(holder_name: "ねこ町のしごと場").account_number
    bank.deposit(@employer, 10_000)
    @teller = Simulation::Teller.new(residents: { "こむぎ" => @komugi, "あずき" => @azuki }, employer_account: @employer)
    @event_store = Rails.configuration.event_store
  end

  test "残高を超える振込は断り（残高が足りない）、お金は動かない" do
    reply = @teller.handle(L::WantTransfer.new(from: "あずき", to: "こむぎ", amount: 51, memo: "おすそわけ", reply_to: nil))

    assert_not reply.ok
    assert_equal :insufficient, reply.reason
    assert_includes reply.message, "残高不足"
    assert_equal 50, reply.balance
    assert_equal 50, balance(@azuki)
    assert_empty @event_store.read.of_type(Banking::Events::TransferDebited).to_a
  end

  test "住民でない相手・自分あて・範囲の外の金額は断る" do
    [
      L::WantTransfer.new(from: "こむぎ", to: "オルカ", amount: 10, memo: "", reply_to: nil),
      L::WantTransfer.new(from: "こむぎ", to: "こむぎ", amount: 10, memo: "", reply_to: nil),
      L::WantTransfer.new(from: "こむぎ", to: "あずき", amount: Simulation::Teller::MAX_TRANSFER + 1, memo: "", reply_to: nil),
      L::WantTransfer.new(from: "こむぎ", to: "あずき", amount: 0, memo: "", reply_to: nil),
      L::AskBalance.new(from: "知らないねこ", reply_to: nil)
    ].each do |letter|
      reply = @teller.handle(letter)
      assert_not reply.ok, letter.inspect
      assert_equal :refused, reply.reason
    end
    assert_equal 100, balance(@komugi)
  end

  test "振込は銀行の入口で書き、出来事に住民の印（resident）と住民の actor が付く" do
    reply = @teller.handle(L::WantTransfer.new(from: "こむぎ", to: "あずき", amount: 30, memo: "おすそわけ", reply_to: nil))

    assert reply.ok, reply.message
    assert_equal 70, reply.balance
    debited = @event_store.read.of_type(Banking::Events::TransferDebited).last
    assert_equal "こむぎ", debited.metadata[:resident]
    assert_equal @komugi.customer.actor, debited.metadata[:actor]
    requested = @event_store.read.of_type(Banking::Events::TransferRequested).last
    assert_equal "こむぎ", requested.metadata[:resident]
    # 印は with_metadata の中だけ。あとで書いた出来事には付かない
    Banking::Bank.new(actor: "test").deposit(@azuki.account_number, 1)
    assert_nil @event_store.read.of_type(Banking::Events::MoneyDeposited).last.metadata[:resident]
  end

  test "給料は給料日に1回だけ、しごと場の口座から振り込む（給料係の actor と住民の印）" do
    salary = L::AskSalary.new(from: "あずき", day: 1, reply_to: nil)
    assert_equal :not_payday, @teller.handle(salary).reason

    @teller.today = L::Tick.new(day: 1, time: :morning, payday: true)
    reply = @teller.handle(salary)
    assert reply.ok, reply.message
    assert_equal 50 + Simulation::Temperament.fetch(:frugal).salary, reply.balance, "お給料は性格で決まる"
    debited = @event_store.read.of_type(Banking::Events::TransferDebited).last
    assert_equal @employer, debited.data[:account_number]
    assert_equal Simulation::Teller::PAYROLL_ACTOR, debited.metadata[:actor]
    assert_equal "あずき", debited.metadata[:resident]

    assert_equal :not_payday, @teller.handle(salary).reason, "同じ日の2回目"
    assert_equal :not_payday, @teller.handle(L::AskSalary.new(from: "あずき", day: 2, reply_to: nil)).reason, "時計と合わない日"
  end

  test "買いものは商店の入口で注文し、売り切れ・残高が足りないときは断る" do
    store = Shop::Store.new(actor: "test")
    store.open_shop
    store.register_product(sku: "churu", name: "ちゅ〜る", price: 30)
    store.register_product(sku: "kotatsu", name: "こたつ", price: 80)
    store.restock("churu", 1)
    store.restock("kotatsu", 5)

    reply = @teller.handle(L::WantPurchase.new(from: "こむぎ", sku: "churu", quantity: 1, reply_to: nil))
    assert reply.ok, reply.message
    assert_equal 70, reply.balance
    placed = @event_store.read.of_type(Shop::Events::OrderPlaced).last
    assert_equal "こむぎ", placed.metadata[:resident]
    assert_equal @komugi.customer.actor, placed.metadata[:actor]

    # 在庫の引き当ては支払いのあと（ジョブ）なので、ここでは読み取りモデルの在庫を減らして売り切れにする
    ShopProduct.find_by!(sku: "churu").update!(stock: 0)
    assert_equal :sold_out, @teller.handle(L::WantPurchase.new(from: "こむぎ", sku: "churu", quantity: 1, reply_to: nil)).reason
    assert_equal :insufficient,
                 @teller.handle(L::WantPurchase.new(from: "あずき", sku: "kotatsu", quantity: 1, reply_to: nil)).reason
    assert_equal :refused, @teller.handle(L::WantPurchase.new(from: "あずき", sku: "nothing", quantity: 1, reply_to: nil)).reason
    assert_equal 1, @event_store.read.of_type(Shop::Events::OrderPlaced).count
  end

  test "家賃は家賃の日に1回だけ、大家さんの口座へ。足りなければ断る" do
    landlord = Banking::Bank.new(actor: "test").open_account(holder_name: "大家さん").account_number
    teller = teller_with(landlord_account: landlord)
    rent = L::PayRent.new(from: "こむぎ", day: 2, reply_to: nil)
    assert_equal :not_payday, teller.handle(rent).reason

    teller.today = L::Tick.new(day: 2, time: :morning, payday: false, rent_day: true)
    reply = teller.handle(rent)
    assert reply.ok, reply.message
    assert_equal 100 - Simulation::Teller::RENT, reply.balance
    assert_equal :not_payday, teller.handle(rent).reason, "同じ日の2回目"
    @azuki.update!(account_number: create_resident("くるみ", deposit: 10).account_number)
    assert_equal :insufficient, teller.handle(L::PayRent.new(from: "あずき", day: 2, reply_to: nil)).reason
  end

  test "遊び場は遊び場の口座へ振り込む。宝くじはときどき当たって、宝くじ屋から賞金" do
    bank = Banking::Bank.new(actor: "test")
    places = %w[cat_cafe lottery].to_h { [ it, bank.open_account(holder_name: it).account_number ] }
    bank.deposit(places["lottery"], 1000)
    lucky = Object.new.tap { it.define_singleton_method(:rand) { 0.0 } }
    teller = teller_with(places:, random: lucky)

    cafe = teller.handle(L::WantFun.new(from: "こむぎ", place: "cat_cafe", reply_to: nil))
    assert cafe.ok, cafe.message
    assert_equal 40, cafe.balance
    lottery = teller.handle(L::WantFun.new(from: "こむぎ", place: "lottery", reply_to: nil))
    assert_includes lottery.message, "当たって"
    assert_equal 40 - 20 + Simulation::Teller::LOTTERY_PRIZE, lottery.balance
    prize = @event_store.read.of_type(Banking::Events::TransferDebited).last
    assert_equal [ places["lottery"], Simulation::Teller::LOTTERY_ACTOR, "こむぎ" ],
                 [ prize.data[:account_number], prize.metadata[:actor], prize.metadata[:resident] ]
    assert_equal :refused, teller.handle(L::WantFun.new(from: "こむぎ", place: "nowhere", reply_to: nil)).reason
  end

  test "ちゅ〜るローン: 借りて、返す。返事にはいつも借金の帳面が付く。上限を超えたら :loan_limit" do
    reply = @teller.handle(L::WantLoan.new(from: "あずき", amount: 100, reply_to: nil))
    assert reply.ok, reply.message
    assert_equal 150, reply.balance
    assert_equal({ L::BANK => 110 }, reply.debts)
    granted = @event_store.read.of_type(Banking::Events::LoanGranted).last
    assert_equal [ "あずき", @azuki.customer.actor ], [ granted.metadata[:resident], granted.metadata[:actor] ]

    @teller.handle(L::WantLoan.new(from: "あずき", amount: 300, reply_to: nil)) # 返す額 330 → 合計 440
    assert_equal :loan_limit, @teller.handle(L::WantLoan.new(from: "あずき", amount: 200, reply_to: nil)).reason

    repaid = @teller.handle(L::WantRepay.new(from: "あずき", to: L::BANK, amount: 500, reply_to: nil))
    assert repaid.ok, repaid.message
    assert_includes repaid.message, "110", "古い貸付から、残りの額まで"
    assert_equal({ L::BANK => 330 }, repaid.debts)
    assert_equal :refused, @teller.handle(L::WantRepay.new(from: "こむぎ", to: L::BANK, amount: 10, reply_to: nil)).reason
  end

  test "住民どうしの貸し借り: 振込と借用書。返すと借用書が減り、借りていない相手には返せない" do
    lent = @teller.handle(L::WantLend.new(from: "こむぎ", to: "あずき", amount: 40, reply_to: nil))
    assert lent.ok, lent.message
    assert_equal 60, lent.balance
    assert_equal({ "こむぎ" => 40 }, Simulation::Debt.owed_by("あずき"))
    assert_equal({ "こむぎ" => 40 }, @teller.handle(L::AskBalance.new(from: "あずき", reply_to: nil)).debts)

    assert_equal :refused, @teller.handle(L::WantLend.new(from: "こむぎ", to: "こむぎ", amount: 10, reply_to: nil)).reason
    assert_equal :refused, @teller.handle(L::WantRepay.new(from: "こむぎ", to: "あずき", amount: 10, reply_to: nil)).reason

    perform_enqueued_jobs # 振込の入金（Solid Queue の係）
    back = @teller.handle(L::WantRepay.new(from: "あずき", to: "こむぎ", amount: 25, reply_to: nil))
    assert back.ok, back.message
    assert_equal({ "こむぎ" => 15 }, back.debts)
    @teller.handle(L::WantRepay.new(from: "あずき", to: "こむぎ", amount: 99, reply_to: nil))
    assert_empty Simulation::Debt.owed_by("あずき"), "残りの額だけ返す"
  end

  private

  def teller_with(**options)
    Simulation::Teller.new(residents: { "こむぎ" => @komugi, "あずき" => @azuki }, employer_account: @employer, **options)
  end

  def balance(status) = Banking::Bank.new(actor: "test").load_account(status.account_number).balance
end
