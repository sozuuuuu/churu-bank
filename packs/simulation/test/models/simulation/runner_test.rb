require "test_helper"
require_relative "../../simulation_test_helper"

# 町を動かす係（メインの Ractor の役場）: 表 simulation_controls に従って町を動かす・止める。住民の手紙に窓口役の返事を出す
class Simulation::RunnerTest < ActiveSupport::TestCase
  include SimulationTestHelper
  include ActionCable::TestHelper

  L = Simulation::Letters

  setup do
    @komugi = create_resident("こむぎ", deposit: 80)
    @azuki = create_resident("あずき", deposit: 0)
    @control = Simulation::Control.current
    @control.update!(employer_account: Banking::Bank.new(actor: "test").open_account(holder_name: "しごと場").account_number,
                     seconds_per_day: 96)
    @runner = Simulation::Runner.new(out: StringIO.new)
  end

  teardown { @runner.send(:stop_town) }

  test "画面で「動かす」なら町を起こし、「止める」なら止める。そのたびに画面へ配る" do
    assert_nil @runner.handle(:check)
    assert_not @control.reload.town_running
    assert @control.heartbeat_at.present?

    @control.update!(running: true)
    assert_broadcasts(Simulation::Board::STREAM, 3) { @runner.handle(:check) } # 住民2匹の回数を 0 に・町の様子
    assert @control.reload.town_running
    assert_equal "動いています（時計の合図を待っています）", @control.status_label

    @control.update!(running: false)
    @runner.handle(:check)
    assert_not @control.reload.town_running
    assert_equal "止まっています", @control.status_label
  end

  test "住民の手紙に窓口役の返事を出し、Report と Restarted を住民の様子の表に書く" do
    @control.update!(running: true)
    @runner.handle(:check)
    port = Ractor::Port.new

    @runner.handle(L::WantTransfer.new(from: "こむぎ", to: "あずき", amount: 30, memo: "おすそわけ", reply_to: port))
    reply = wait_for(port) { true }
    assert reply.ok, reply.message
    assert_equal 50, reply.balance

    @runner.handle(L::Report.new(name: "こむぎ", state: "ぶらぶら", mood: 77, money: 50, last_action: "振り込んだ"))
    @runner.handle(L::Restarted.new(name: "こむぎ", count: 2, reason: "ころんだ（Stumbled）"))
    @komugi.reload
    assert_equal [ "ぶらぶら", 77, 50, "振り込んだ", 2, "ころんだ（Stumbled）" ],
                 @komugi.attributes.values_at("state", "mood", "money", "last_action", "restarts", "last_error")
    assert @komugi.last_action_at.present?
  end

  test "閉じた受け口（返事を待たずに倒れた住民）には返事を出さずに続ける" do
    port = Ractor::Port.new
    port.close
    assert_nothing_raised { @runner.handle(L::AskBalance.new(from: "こむぎ", reply_to: port)) }
  end
end
