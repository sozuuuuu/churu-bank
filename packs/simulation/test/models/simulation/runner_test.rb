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

  test "行員がいると、ローンはすぐ貸さない。たまへ申込を届け、決裁が来たら行員の actor で貸して返事を出す" do
    tama, kuro = create_clerks
    @control.update!(running: true)
    @runner.handle(:check)
    delivered = []
    @runner.instance_variable_get(:@town).define_singleton_method(:deliver) { |name, letter| delivered << [ name, letter ] }
    port = Ractor::Port.new

    @runner.handle(L::WantLoan.new(from: "あずき", amount: 100, reply_to: port))
    kase = Simulation::LoanCase.last
    assert_equal [ "あずき", 100, "applied" ], [ kase.resident, kase.amount, kase.status ]
    assert_equal "窓口のたま", delivered.last[0]
    assert_equal L::Case.new(id: kase.id, from: "窓口役", resident: "あずき", amount: 100, owed: 0, salary: 170, overdue: 0),
                 delivered.last[1], "試験のあずきは倹約家（お給料 170）"
    assert_empty Loan.all, "決裁までは貸さない"

    @runner.handle(L::Decision.new(from: "窓口のたま", case_id: kase.id, approve: true, reason: "返せそう"))
    reply = wait_for(port) { true }
    assert reply.ok, reply.message
    assert_equal({ L::BANK => 110 }, reply.debts)
    granted = Rails.configuration.event_store.read.of_type(Banking::Events::LoanGranted).last
    assert_equal [ tama.staff.actor, "あずき" ], [ granted.metadata[:actor], granted.metadata[:resident] ]
    assert_equal [ "approved", "窓口のたま", granted.data[:loan_id] ], kase.reload.then { [ it.status, it.decided_by, it.loan_id ] }

    @runner.handle(L::WantLoan.new(from: "あずき", amount: 160, reply_to: port))
    second = Simulation::LoanCase.last
    @runner.handle(L::Copy.new(from: "窓口役", to: "窓口のたま", letter: delivered.last[1]))
    assert_equal "applied", second.reload.status, "役場からたまへ届けた写しは「回した」にしない"
    @runner.handle(L::Copy.new(from: "窓口のたま", to: "係長のくろ", letter: delivered.last[1].with(from: "窓口のたま")))
    assert_equal [ "forwarded", "窓口のたま" ], second.reload.then { [ it.status, it.handled_by ] }
    @runner.handle(L::Decision.new(from: kuro.name, case_id: second.id, approve: false, reason: "お給料より多い"))
    refused = wait_for(port) { true }
    assert_not refused.ok
    assert_equal :loan_rejected, refused.reason
    assert_includes refused.message, "お給料より多い"
    assert_equal "rejected", second.reload.status
  end

  test "係長に延滞を返し、督促した日を書く。同じ日にもう一度聞いても出ない" do
    create_clerks
    @control.update!(running: true, day: 9)
    @runner.handle(:check)
    bank = Banking::Bank.new(actor: "test")
    loan_id = bank.lend(@azuki.account_number, 100).loan_id
    kase = Simulation::LoanCase.create!(resident: "あずき", amount: 100, status: "approved", loan_id:, day: 1, decided_day: 1)
    other_id = bank.lend(@azuki.account_number, 50).loan_id
    Simulation::LoanCase.create!(resident: "あずき", amount: 50, status: "approved", loan_id: other_id, day: 2, decided_day: 2)
    @runner.handle(L::Tick.new(day: 9, time: :morning, payday: false))
    port = Ractor::Port.new

    @runner.handle(L::AskOverdue.new(from: "係長のくろ", reply_to: port))
    assert_equal [ L::OverdueItem.new(resident: "あずき", owed: 110 + 55, days: 8) ], wait_for(port) { true }.items,
                 "住民ごとに1通（2つのローンを合わせる）"
    assert_equal 9, kase.reload.last_dunned_day
    @runner.handle(L::AskOverdue.new(from: "係長のくろ", reply_to: port))
    assert_empty wait_for(port) { true }.items
  end

  test "町を起こすとき、決まらずに残った申込は取り下げにする" do
    create_clerks
    old = Simulation::LoanCase.create!(resident: "あずき", amount: 50, status: "applied", day: 1)
    @control.update!(running: true)
    @runner.handle(:check)
    assert_equal "withdrawn", old.reload.status
  end

  test "閉じた受け口（返事を待たずに倒れた住民）には返事を出さずに続ける" do
    port = Ractor::Port.new
    port.close
    assert_nothing_raised { @runner.handle(L::AskBalance.new(from: "こむぎ", reply_to: port)) }
  end
end
