# 時計役（Ractor 1 つ）: 「朝・昼・夕方・夜」の合図（Letters::Tick）を、郵便屋を通して住民みんなへ、役場にも配る。
# 1日を seconds_per_day 秒に縮める（ふだんは 24 秒 = 合図は 6 秒ごと）。給料日は PAYDAY_EVERY 日ごとの朝。
#
# Ractor の中に糸（Thread）を2本: 1本は手紙（Letters::Speed で速さを変える・:stop で止まる）を待ち、
# もう1本（Ractor のはじめの糸）が合図を出す。待っているあいだも 0.05 秒ごとに速さを見直すので、速さの変更はすぐ効く
module Simulation
  class Clock
    TIMES = %i[morning noon evening night].freeze
    PAYDAY_EVERY = 3
    FIRST_TICK_AFTER = 0.3 # 住民が郵便屋の帳面に載るのを少し待つ

    def self.spawn(postman:, hall:, seconds_per_day:, day: 1)
      Ractor.new(postman, hall, seconds_per_day, day, name: "時計役") do |post, town_hall, seconds, first_day|
        Clock.new(postman: post, hall: town_hall, seconds_per_day: seconds, day: first_day).run
      end
    end

    # step 番目（0 から）の合図。1日目の朝が 0
    def self.tick_at(step, first_day: 1)
      day = first_day + (step / TIMES.size)
      time = TIMES[step % TIMES.size]
      Letters::Tick.new(day:, time:, payday: time == :morning && ((day - 1) % PAYDAY_EVERY).zero?)
    end

    def initialize(postman:, hall:, seconds_per_day:, day:)
      @postman = postman
      @hall = hall
      @seconds_per_day = seconds_per_day.to_f
      @day = day
      @stopped = false
    end

    def run
      listener = Thread.new { listen }
      wait(FIRST_TICK_AFTER)
      step = 0
      until @stopped
        tick = self.class.tick_at(step, first_day: @day)
        @postman << Letters::Broadcast.new(letter: tick)
        @hall << tick
        step += 1
        wait_until(Process.clock_gettime(Process::CLOCK_MONOTONIC)) { @seconds_per_day / TIMES.size }
      end
      listener.kill
    end

    private

    def listen
      loop do
        case (letter = Ractor.receive)
        when :stop then break @stopped = true
        when Letters::Speed then @seconds_per_day = letter.seconds_per_day.to_f
        end
      end
    end

    def wait(seconds) = wait_until(Process.clock_gettime(Process::CLOCK_MONOTONIC)) { seconds }

    # 始めた時刻から「いまの間隔」が過ぎるか、止められるまで待つ
    def wait_until(started)
      sleep 0.05 until @stopped || Process.clock_gettime(Process::CLOCK_MONOTONIC) - started >= yield
    end
  end
end
