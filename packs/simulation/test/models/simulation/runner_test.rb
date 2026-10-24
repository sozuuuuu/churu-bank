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
    assert_broadcasts(Simulation::Board::STREAM, 7) { @runner.handle(:check) } # 住民2匹（窓と地図の上）の回数を 0 に・借金の関係図・町の様子と空
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

  test "手紙（頼みと返事・郵便屋の写し・起こし直し）を「手紙の流れ」に書き残し、時計の合図は残さない" do
    @control.update!(running: true)
    @runner.handle(:check)
    port = Ractor::Port.new

    @runner.handle(L::Tick.new(day: 3, time: :noon, payday: false))
    @runner.handle(L::WantTransfer.new(from: "こむぎ", to: "あずき", amount: 500, memo: "おすそわけ", reply_to: port))
    wait_for(port) { true }
    @runner.handle(L::Copy.new(from: "あずき", to: "みんな", letter: L::Trouble.new(from: "あずき", amount: 30)))
    @runner.handle(L::Restarted.new(name: "あずき", count: 1, reason: "ころんだ"))

    letters = Simulation::Letter.order(:id).map { [ it.sender, it.recipient, it.kind, it.day ] }
    assert_equal [ [ "こむぎ", "窓口役", "ask", 3 ], [ "窓口役", "こむぎ", "refuse", 3 ], [ "あずき", "みんな", "trouble", 3 ],
                   [ "見張り役", "あずき", "restart", 3 ] ], letters
    assert_includes Simulation::Letter.first.text, "あずきさんへ 500 ちゅ〜る振り込みたい"
  end

  test "住民どうしで貸せたら、借りた住民へ「貸してもらえたよ」を郵便屋に届けてもらう" do
    @control.update!(running: true)
    @runner.handle(:check)
    town = @runner.instance_variable_get(:@town)
    delivered = []
    town.define_singleton_method(:deliver) { |name, letter| delivered << [ name, letter ] }
    port = Ractor::Port.new

    @runner.handle(L::WantLend.new(from: "こむぎ", to: "あずき", amount: 30, reply_to: port))
    assert wait_for(port) { true }.ok
    assert_equal [ [ "あずき", L::Lent.new(from: "こむぎ", amount: 30) ] ], delivered
  end

  test "閉じた受け口（返事を待たずに倒れた住民）には返事を出さずに続ける" do
    port = Ractor::Port.new
    port.close
    assert_nothing_raised { @runner.handle(L::AskBalance.new(from: "こむぎ", reply_to: port)) }
  end
end
