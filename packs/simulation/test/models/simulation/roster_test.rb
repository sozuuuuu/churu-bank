require "test_helper"
require_relative "../../simulation_test_helper"

# 町の用意（大家さん・遊び場の口座）と、財布を整える（たまりすぎた分を基金へ）
class Simulation::RosterTest < ActiveSupport::TestCase
  include SimulationTestHelper

  test "用意すると大家さんと遊び場の口座ができ、何度流しても増えない" do
    Simulation::Roster.setup!(residents: [])
    control = Simulation::Control.current
    places = control.places

    assert control.landlord_account.present?
    assert_equal Simulation::Roster::PLACES.map(&:key).sort, places.keys.sort
    assert_equal Simulation::Roster::LOTTERY_FUNDS, Account.find_by!(number: places["lottery"]).balance

    Simulation::Roster.setup!(residents: [])
    assert_equal places, control.reload.places
  end

  test "財布を整えると、keep を超える分だけ基金へ振り込む（振込なので記録に残る）" do
    komugi = create_resident("こむぎ", deposit: 900)
    create_resident("あずき", deposit: 100)

    moved = Simulation::Roster.trim_wallets!(keep: 200)

    assert_equal({ "こむぎ" => 700 }, moved)
    assert_equal 200, Banking::Bank.new(actor: "test").load_account(komugi.account_number).balance
    fund = Simulation::Control.current.places.fetch("fund")
    debited = Rails.configuration.event_store.read.of_type(Banking::Events::TransferDebited).last
    assert_equal [ komugi.account_number, fund, Simulation::Roster::FUND_ACTOR ],
                 [ debited.data[:account_number], debited.data[:counterparty], debited.metadata[:actor] ]
  end
end
