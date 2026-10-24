require "test_helper"
require_relative "../../simulation_test_helper"

# 行員エージェント（窓口のたま・係長のくろ）: 頭の決まり、行員の Ractor、延滞の判定
class Simulation::ClerksTest < ActiveSupport::TestCase
  include SimulationTestHelper

  L = Simulation::Letters

  def kase(amount: 100, owed: 0, salary: 170, overdue: 0, from: "窓口役")
    L::Case.new(id: 1, from:, resident: "あずき", amount:, owed:, salary:, overdue:)
  end

  def verdict(role, **) = Simulation::ClerkRules.new(role:).review(kase(**))

  test "たま: ふつうは承認、延滞・借りすぎは却下、150 以上は係長へ回す" do
    assert_equal :approve, verdict(:teller).action
    assert_equal :reject, verdict(:teller, overdue: 1).action
    assert_includes verdict(:teller, owed: 400).reason, "借りすぎ" # 400 + 110 = 510 > 480
    assert_equal :forward, verdict(:teller, amount: 150).action
  end

  test "くろ: たまより厳しい（返す額が上限の 6 割まで・お給料より多くは貸さない）" do
    assert_equal :approve, verdict(:chief, amount: 150).action
    assert_equal :reject, verdict(:chief, amount: 150, owed: 200).action # 200 + 165 = 365 > 360
    assert_equal :reject, verdict(:chief, amount: 200, salary: 160).action
    assert_equal :approve, verdict(:teller, owed: 300).action, "たまなら 300 + 110 = 410 でも通す"
    assert_equal :reject, verdict(:chief, owed: 300).action
  end

  test "行員（Ractor の外で）: 申込を見て、決裁を役場へ・係長へは郵便屋で回す。係長は朝に延滞を聞き、督促状を出す" do
    hall, postman = Ractor::Port.new, Ractor::Port.new
    spec = Simulation::Clerk::Spec.new(name: "窓口のたま", role: :teller, chief: "係長のくろ")
    tama = Simulation::Clerk.new(spec, restarts: 0, hall:, postman:)

    tama.hear(kase)
    decision = wait_for(hall) { it.is_a?(L::Decision) }
    assert_equal [ "窓口のたま", 1, true ], [ decision.from, decision.case_id, decision.approve ]
    report = wait_for(hall) { it.is_a?(L::ClerkReport) }
    assert_equal [ 1, 1 ], [ report.handled, report.approved ]

    tama.hear(kase(amount: 200))
    forwarded = wait_for(postman) { true }
    assert_equal "係長のくろ", forwarded.to
    assert_equal [ "窓口のたま", 200 ], [ forwarded.letter.from, forwarded.letter.amount ]

    kuro = Simulation::Clerk.new(Simulation::Clerk::Spec.new(name: "係長のくろ", role: :chief, chief: "係長のくろ"),
                                 restarts: 0, hall:, postman:)
    kuro.hear(L::Tick.new(day: 3, time: :morning, payday: false))
    assert_equal "係長のくろ", wait_for(hall) { it.is_a?(L::AskOverdue) }.from
    kuro.hear(L::Overdue.new(items: [ L::OverdueItem.new(resident: "あずき", owed: 110, days: 7) ]))
    dun = wait_for(postman) { it.letter.is_a?(L::Dun) }
    assert_equal [ "あずき", L::Dun.new(from: "係長のくろ", amount: 110) ], [ dun.to, dun.letter ]
    assert_equal "あずきの家へ督促に行った", kuro.state
  end

  test "行員（本物の Ractor）: 見張り役が作り、郵便屋の帳面に載って、申込に決裁を返す" do
    hall = Ractor::Port.new
    postman = Simulation::Postman.spawn(hall:)
    specs = [ Simulation::Clerk::Spec.new(name: "窓口のたま", role: :teller, chief: "係長のくろ"),
              Simulation::Clerk::Spec.new(name: "係長のくろ", role: :chief, chief: "係長のくろ") ]
    Simulation::Town.preload
    supervisor = Simulation::Supervisor.spawn(specs: Ractor.make_shareable(specs), hall:, postman:)
    arrived = []
    wait_for(hall) { arrived << it.name if it.is_a?(L::ClerkReport) && it.last_action == "出勤した"; arrived.size == 2 }
    assert_equal %w[係長のくろ 窓口のたま], arrived.sort

    postman << L::Deliver.new(to: "窓口のたま", letter: kase(amount: 160))
    decision = wait_for(hall) { it.is_a?(L::Decision) }
    assert_equal [ "係長のくろ", true ], [ decision.from, decision.approve ], "たまが係長へ回し、くろが決裁した"

    supervisor << :stop
    join_within(supervisor)
    postman << :stop
    join_within(postman)
  end

  test "延滞: 借りた日か最後に返した日から 6 日以上。督促は 3 日ごと。完済したら延滞ではない" do
    bank = Banking::Bank.new(actor: "test")
    number = bank.open_account(holder_name: "あずき").account_number
    loan_id = bank.lend(number, 100).loan_id
    loan = Simulation::LoanCase.create!(resident: "あずき", amount: 100, status: "approved", loan_id:, day: 1, decided_day: 1)

    assert_empty Simulation::LoanCase.overdue(6)
    assert_equal [ loan ], Simulation::LoanCase.overdue(7)
    loan.update!(last_dunned_day: 7)
    assert_empty Simulation::LoanCase.to_dun(9)
    assert_equal [ loan ], Simulation::LoanCase.to_dun(10)

    loan.update!(last_repaid_day: 8)
    assert_empty Simulation::LoanCase.overdue(13)
    bank.deposit(number, 10)
    bank.repay_loan(loan_id, 110)
    assert_empty Simulation::LoanCase.overdue(30)
  end
end
