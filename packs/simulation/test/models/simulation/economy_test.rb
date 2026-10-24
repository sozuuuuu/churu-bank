require "test_helper"

# 町のお金のめぐり: 大家さん・遊び場は残すぶんをこえたお金をしごと場へ。商店は仕入れ代をしごと場に払って入荷する
class Simulation::EconomyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @bank = Banking::Bank.new(actor: "test")
    @employer = @bank.open_account(holder_name: "しごと場").account_number
    @landlord = @bank.open_account(holder_name: "大家さん").account_number
    @cafe = @bank.open_account(holder_name: "ねこカフェ").account_number
    @lottery = @bank.open_account(holder_name: "宝くじ").account_number
    @fund = @bank.open_account(holder_name: "基金").account_number
    @control = Simulation::Control.current
    @control.update!(employer_account: @employer, landlord_account: @landlord,
                     places: { "cat_cafe" => @cafe, "lottery" => @lottery, "fund" => @fund })
  end

  def balance(number) = Account.find_by!(number:).balance

  test "大家さんと遊び場は、残すぶんをこえたお金をしごと場へ払う。宝くじは多めに残し、基金はふくめない" do
    { @landlord => 1_000, @cafe => 200, @lottery => 5_000, @fund => 9_000 }.each { |number, amount| @bank.deposit(number, amount) }

    paid = perform_enqueued_jobs { Simulation::Economy.sweep!(@control) }

    assert_equal({ "大家さん" => 700, "宝くじ" => 2_000 }, paid)
    assert_equal 2_700, balance(@employer)
    assert_equal [ 300, 200, 3_000, 9_000 ], [ @landlord, @cafe, @lottery, @fund ].map { balance(it) }
    assert_empty Simulation::Economy.sweep!(@control), "2回目は払うぶんがない"
  end

  test "商店も、仕入れ代のぶんを残して、こえたぶんをしごと場へ払う" do
    store = Shop::Store.new(actor: "test")
    store.open_shop
    @bank.deposit(store.account_number, 2_500)

    paid = perform_enqueued_jobs { Simulation::Economy.sweep!(@control) }

    assert_equal 500, paid.fetch(Shop::Store::SHOP_NAME)
    assert_equal Simulation::Economy::SHOP_KEEP, balance(store.account_number)
  end

  test "商店は仕入れ代（値段の 6 割）をしごと場に払って入荷する。払えるぶんだけ" do
    store = Shop::Store.new(actor: "test")
    store.open_shop
    store.register_product(sku: "churu", name: "ちゅ〜る", price: 30)
    store.register_product(sku: "kotatsu", name: "こたつ", price: 1_500)
    @bank.deposit(store.account_number, 900)

    stocked = perform_enqueued_jobs { Simulation::Economy.restock!(@control) }

    # ちゅ〜るは 30 こまで（1 こ 18、30 こで 540）。こたつは 1 こ 900 なので、残り 360 では入荷できない
    assert_equal({ "churu" => 30 }, stocked)
    assert_equal 30, ShopProduct.find_by!(sku: "churu").stock
    assert_equal 0, ShopProduct.find_by!(sku: "kotatsu").stock
    assert_equal 540, balance(@employer)
    assert_equal 360, balance(store.account_number)
    debited = Rails.configuration.event_store.read.of_type(Banking::Events::TransferDebited).last
    assert_equal Simulation::Economy::ACTOR, debited.metadata[:actor]
  end
end
