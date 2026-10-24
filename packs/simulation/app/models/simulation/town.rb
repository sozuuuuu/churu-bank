# ねこ町: 郵便屋・見張り役（とその下の住民たち）・時計役の Ractor を、まとめて動かす・止める。メインの Ractor から使う。
#
#   メインの Ractor（役場: 窓口役と画面の係）◀── 手紙 ──┐
#     │ hall（役場の受け口）                              │
#     ├─ 郵便屋 ─▶ 住民の受け口へ配る                     │
#     ├─ 見張り役 ─┬─ 住民 ─────────────────────────────┤
#     │            ├─ 住民 ─────────────────────────────┤
#     │            └─ …                                  │
#     └─ 時計役 ─▶ 郵便屋（住民みんなへ）・役場 ──────────┘
#
# Ractor の中ではクラスを読み込めない（Zeitwerk の自動読み込みは require を使う）ので、
# 動かす前にメインで Ractor の側のクラスを全部読み込んでおく（PRELOAD）
module Simulation
  class Town
    PRELOAD = %w[
      Simulation::Letters Simulation::Intent Simulation::Temperament Simulation::Memory Simulation::Brain
      Simulation::Brains Simulation::Brains::Rules Simulation::Brains::Haiku Simulation::Resident
      Simulation::Postman Simulation::Clock Simulation::Supervisor
    ].freeze

    def self.preload
      Warning[:experimental] = false # 「Ractor はまだ試しの機能」の注意を毎回出さない
      PRELOAD.each(&:constantize)
    end

    def initialize(specs:, hall:, seconds_per_day:, day: 1)
      @specs = Ractor.make_shareable(specs)
      @hall = hall
      @seconds_per_day = seconds_per_day
      @day = day
    end

    def start
      self.class.preload
      @postman = Postman.spawn
      @supervisor = Supervisor.spawn(specs: @specs, hall: @hall, postman: @postman)
      @clock = Clock.spawn(postman: @postman, hall: @hall, seconds_per_day: @seconds_per_day, day: @day)
      self
    end

    def running? = !@clock.nil?

    def speed=(seconds_per_day)
      @clock << Letters::Speed.new(seconds_per_day:)
    end

    # 名前の住民に手紙を渡す（見張り役を通す。試験で :crash を渡して倒すとき）
    def poke(name, letter)
      @supervisor << Letters::Poke.new(name:, letter:)
    end

    # 時計 → 見張り役（住民みんなが町を出るのを待つ）→ 郵便屋 の順に止める
    def stop
      [ @clock, @supervisor, @postman ].compact.each do |ractor|
        ractor << :stop
        ractor.join
      rescue Ractor::ClosedError, Ractor::RemoteError
        nil
      end
      @clock = @supervisor = @postman = nil
    end
  end
end
