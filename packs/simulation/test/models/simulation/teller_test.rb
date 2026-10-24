require "test_helper"
require_relative "../../simulation_test_helper"

# 窓口役: 住民の手紙を確かめてから、銀行と商店の公開の入口で書く。断ったら返事でわけを伝える
class Simulation::TellerTest < ActiveSupport::TestCase
  include SimulationTestHelper

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
    assert_equal 50 + Simulation::Teller::SALARY, reply.balance
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

  private

  def balance(status) = Banking::Bank.new(actor: "test").load_account(status.account_number).balance
end
