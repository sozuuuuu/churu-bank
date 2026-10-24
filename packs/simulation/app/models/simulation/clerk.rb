# 行員 1 人 = Ractor 1 つ（住民と同じ、Erlang のプロセスのつもり）。窓口のたまと係長のくろ。
# 住民と同じく見張り役が見張り、郵便屋の帳面に載る（時計の合図も届く）。銀行には触らず、役場（メインの Ractor）へ手紙で決めたことを伝える。
#
#   Case（ローンの申込）が届く → 頭（ClerkRules）に聞く → 承認・却下なら Decision を役場へ、係長へ回すなら郵便屋で係長へ Case を
#   朝の合図（係長だけ）→ 役場に AskOverdue → Overdue が返る → 延滞している住民へ郵便屋で Dun（督促状）
#
# 書き込み（貸す）は役場が、この行員の actor（staff:<id>）で行う。だから出来事に「窓口のたま」「係長のくろ」の名前が残る
module Simulation
  class Clerk
    # role は :teller（窓口）/ :chief（係長）、chief は回す先の係長の名前
    Spec = Data.define(:name, :role, :chief) do
      def agent_class = Clerk
    end

    def self.spawn(spec, restarts:, hall:, postman:)
      Ractor.new(spec, restarts, hall, postman, name: "行員 #{spec.name}") do |s, count, town_hall, post|
        Thread.current.report_on_exception = false # 倒れたわけは見張り役が役場へ知らせる
        Clerk.new(s, restarts: count, hall: town_hall, postman: post).run
      end
    end

    attr_reader :state, :last_action, :counts

    def initialize(spec, restarts:, hall:, postman:)
      @spec = spec
      @restarts = restarts
      @hall = hall
      @postman = postman
      @brain = ClerkRules.new(role: spec.role)
      @state = "銀行の窓口にいる"
      @counts = { handled: 0, approved: 0, rejected: 0, forwarded: 0, dunned: 0 }
    end

    def name = @spec.name

    def chief? = @spec.role.to_sym == :chief

    def run
      report(@restarts.zero? ? "出勤した" : "見張り役に起こし直してもらった（#{@restarts} 回目）")
      loop do
        letter = Ractor.receive
        break if letter == :stop

        hear(letter)
      end
      @state = "家に帰った"
      report("おつかれさま（町を出た）")
    end

    # 手紙を1通聞く（Ractor の外の試験からも呼べる）
    def hear(letter)
      raise Resident::Stumbled, "#{name}が書類につまずいてころんだ" if letter == :crash

      note = case letter
      when Letters::Tick then on_tick(letter)
      when Letters::Case then review(letter)
      when Letters::Overdue then dun(letter)
      end
      report(note) if note
    end

    private

    def inbox = Ractor.current.default_port

    # 時計の合図で窓口に戻る（督促に出ていたら、画面のために知らせる）。係長は朝に延滞を調べる
    def on_tick(tick)
      away = @state != "銀行の窓口にいる"
      @state = "銀行の窓口にいる"
      if chief? && tick.time == :morning
        @hall << Letters::AskOverdue.new(from: name, reply_to: inbox)
        return "延滞しているローンを調べている"
      end
      "銀行の窓口に戻った" if away
    end

    def review(kase)
      @counts[:handled] += 1
      verdict = @brain.review(kase)
      case verdict.action
      when :forward
        @counts[:forwarded] += 1
        @postman << Letters::Deliver.new(to: @spec.chief, letter: kase.with(from: name))
        "#{kase.resident}さんの申込（#{kase.amount} ちゅ〜る）を係長に回した"
      else
        approve = verdict.action == :approve
        @counts[approve ? :approved : :rejected] += 1
        @hall << Letters::Decision.new(from: name, case_id: kase.id, approve:, reason: verdict.reason)
        "#{kase.resident}さんの申込（#{kase.amount} ちゅ〜る）を#{approve ? "承認" : "却下"}した"
      end
    end

    def dun(overdue)
      return if overdue.items.empty?

      overdue.items.each do |item|
        @counts[:dunned] += 1
        @postman << Letters::Deliver.new(to: item.resident, letter: Letters::Dun.new(from: name, amount: item.owed))
      end
      @state = "#{overdue.items.last.resident}の家へ督促に行った"
      "#{overdue.items.map(&:resident).join("・")}さんに督促状を出した"
    end

    def report(note)
      @last_action = note
      @hall << Letters::ClerkReport.new(name:, state: @state, last_action: note, **@counts)
    end
  end
end
