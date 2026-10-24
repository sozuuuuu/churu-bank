require "test_helper"
require_relative "../../simulation_test_helper"

# 住民: 手紙を聞いて、記憶を覚えなおし、頭の答えを手紙にして出す。ここでは Ractor の外で hear を直接呼ぶ
class Simulation::ResidentTest < ActiveSupport::TestCase
  include SimulationTestHelper

  L = Simulation::Letters

  setup do
    Simulation::Town.preload
    @hall = Ractor::Port.new
    @postman = Ractor::Port.new
    @resident = Simulation::Resident.new(spec_for("こむぎ", friends: [ "あずき" ]), restarts: 0, hall: @hall, postman: @postman)
  end

  test "給料日の朝の合図で、窓口役へ給料を頼み、役場へ様子を知らせる" do
    @resident.hear(L::Tick.new(day: 4, time: :morning, payday: true))

    salary = wait_for(@hall) { it.is_a?(L::AskSalary) }
    assert_equal "こむぎ", salary.from
    assert_equal 4, salary.day
    assert_equal Ractor.current.default_port, salary.reply_to
    report = wait_for(@hall) { it.is_a?(L::Report) }
    assert_equal "しごと場で働いている", report.state
    assert_equal "働いた。窓口に給料を頼んだ", report.last_action
  end

  test "窓口役の返事で所持金の見込みを覚えなおし、断られると気分が下がる" do
    request = L::AskBalance.new(from: "こむぎ", reply_to: nil)
    @resident.hear(L::Reply.new(request:, ok: true, message: "残高は 300 ちゅ〜るです", balance: 300))
    report = wait_for(@hall) { it.is_a?(L::Report) }
    assert_equal 300, report.money
    assert_equal "窓口: 残高は 300 ちゅ〜るです", report.last_action

    mood = @resident.memory.mood
    want = L::WantTransfer.new(from: "こむぎ", to: "あずき", amount: 500, memo: "", reply_to: nil)
    @resident.hear(L::Reply.new(request: want, ok: false, message: "残高が足りません", balance: 300, reason: :refused))
    assert_operator @resident.memory.mood, :<, mood
    assert_equal "窓口に断られた: 残高が足りません", wait_for(@hall) { it.is_a?(L::Report) }.last_action
  end

  test "手紙はどれも Ractor で共有できる（写しを作らずに送れる）" do
    @resident.hear(L::Tick.new(day: 1, time: :morning, payday: true))
    letter = wait_for(@hall) { it.is_a?(L::AskSalary) }
    assert Ractor.shareable?(L::Tick.new(day: 1, time: :noon, payday: false))
    assert Ractor.shareable?(letter)
    assert Ractor.shareable?(Simulation::Temperament::ALL)
  end

  test ":crash でわざと倒れる" do
    error = assert_raises(Simulation::Resident::Stumbled) { @resident.hear(:crash) }
    assert_includes error.message, "こむぎ"
  end
end
