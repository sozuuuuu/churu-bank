require "test_helper"
require_relative "../../simulation_test_helper"

# Ractor を本当に動かす試験（見張り役・時計役・郵便屋・町）。待つ時間には上限をつけ、どれも 1 秒前後で終わる
class Simulation::RactorsTest < ActiveSupport::TestCase
  include SimulationTestHelper

  L = Simulation::Letters

  setup do
    Simulation::Town.preload
    @hall = Ractor::Port.new
  end

  test "見張り役: 倒れた住民を起こし直して回数を数え、郵便屋の帳面を新しい受け口に書きなおす" do
    postman = Ractor::Port.new
    supervisor = Simulation::Supervisor.spawn(specs: [ spec_for("こむぎ"), spec_for("あずき") ], hall: @hall, postman:)
    first = wait_for(postman) { it.is_a?(L::Register) && it.name == "こむぎ" }
    wait_for(@hall) { it.is_a?(L::AskBalance) && it.from == "こむぎ" }

    supervisor << L::Poke.new(name: "こむぎ", letter: :crash)
    restarted = wait_for(@hall) { it.is_a?(L::Restarted) }
    assert_equal "こむぎ", restarted.name
    assert_equal 1, restarted.count
    assert_includes restarted.reason, "ころんだ"
    assert_includes restarted.reason, "Stumbled"
    again = wait_for(postman) { it.is_a?(L::Register) && it.name == "こむぎ" }
    assert_not_equal first.port, again.port, "起こし直した住民の受け口は新しい"
    awake = wait_for(@hall) { it.is_a?(L::Report) && it.name == "こむぎ" }
    assert_equal "見張り役に起こし直してもらった（1 回目）", awake.last_action
    wait_for(@hall) { it.is_a?(L::AskBalance) && it.from == "こむぎ" } # 起きたら残高を聞き直す

    supervisor << L::Poke.new(name: "こむぎ", letter: :crash)
    assert_equal 2, wait_for(@hall) { it.is_a?(L::Restarted) }.count

    supervisor << :stop
    join_within(supervisor)
  end

  test "時計役: 朝・昼・夕方・夜の合図を郵便屋と役場へ配り、速さを変えられ、:stop で止まる" do
    postman = Ractor::Port.new
    clock = Simulation::Clock.spawn(postman:, hall: @hall, seconds_per_day: 0.4, day: 3)

    ticks = Array.new(4) { wait_for(@hall) { it.is_a?(L::Tick) } }
    assert_equal %i[morning noon evening night], ticks.map(&:time)
    assert_equal [ 3 ] * 4, ticks.map(&:day)
    broadcast = wait_for(postman) { it.is_a?(L::Broadcast) }
    assert_equal L::Tick.new(day: 3, time: :morning, payday: false), broadcast.letter

    clock << L::Speed.new(seconds_per_day: 3600)
    clock << :stop
    join_within(clock, seconds: 1)
  end

  test "時計役の合図の順番と給料日（1日目から 3 日ごとの朝）" do
    ticks = (0...16).map { Simulation::Clock.tick_at(it) }
    assert_equal [ 1, :morning, true ], ticks[0].to_h.values_at(:day, :time, :payday)
    assert_equal [ 1, :night, false ], ticks[3].to_h.values_at(:day, :time, :payday)
    assert_equal [ 1, 4 ], ticks.select(&:payday).map(&:day)
    assert Simulation::Clock.tick_at(0, first_day: 7).payday
  end

  test "郵便屋: Broadcast は送り主のほかのみんなへ。倒れた住民の閉じた受け口は飛ばす" do
    postman = Simulation::Postman.new
    komugi, azuki, closed = Ractor::Port.new, Ractor::Port.new, Ractor::Port.new
    closed.close
    { "こむぎ" => komugi, "あずき" => azuki, "ころん" => closed }.each { postman.handle(L::Register.new(name: _1, port: _2)) }

    postman.handle(L::Broadcast.new(letter: L::Trouble.new(from: "こむぎ", amount: 30), except: "こむぎ"))
    assert_equal L::Trouble.new(from: "こむぎ", amount: 30), wait_for(azuki) { true }
    postman.handle(L::Broadcast.new(letter: :hello))
    assert_equal :hello, wait_for(komugi) { true }, "こむぎには Trouble は届かず、次の手紙が先頭"
  end

  test "町: 動かすと住民が起きて残高を聞き、時計が鳴り、止めるとみんな町を出る" do
    specs = [ spec_for("こむぎ", friends: [ "あずき" ]), spec_for("あずき", temperament: :impulsive, friends: [ "こむぎ" ]) ]
    town = Simulation::Town.new(specs:, hall: @hall, seconds_per_day: 0.8).start

    asked = [ wait_for(@hall) { it.is_a?(L::AskBalance) }, wait_for(@hall) { it.is_a?(L::AskBalance) } ]
    assert_equal %w[あずき こむぎ], asked.map(&:from).sort
    # 給料日の朝なので、2匹とも働いて給料を頼む（時計の合図が郵便屋を通って住民に届いた）
    salaries = [ wait_for(@hall) { it.is_a?(L::AskSalary) }, wait_for(@hall) { it.is_a?(L::AskSalary) } ]
    assert_equal %w[あずき こむぎ], salaries.map(&:from).sort
    assert_equal [ 1, 1 ], salaries.map(&:day)

    stopper = Thread.new { town.stop }
    assert stopper.join(3), "3 秒で止まる"
    bye = [ wait_for(@hall) { it.is_a?(L::Report) && it.state == "町を出た" },
            wait_for(@hall) { it.is_a?(L::Report) && it.state == "町を出た" } ]
    assert_equal %w[あずき こむぎ], bye.map(&:name).sort
    assert_not town.running?
  end
end
