# 行員の頭（決まりで動く）。ローンの申込（Letters::Case）を見て、承認・却下・係長へ回す、を決める。
#
#   窓口のたま（:teller）… 延滞がある → 却下。借りたあとの返す額が上限の 8 割を超える → 却下。
#                          FORWARD_AT 以上 → 係長へ回す。それ以外 → 承認
#   係長のくろ（:chief） … 延滞がある → 却下。借りたあとの返す額が上限の 6 割を超える → 却下。
#                          お給料より多く借りたい → 却下。それ以外 → 承認（たまより少し厳しい）
#
# 頭は決めるだけ。手紙を出さない・DB に触らない（それは行員の Ractor と役場の仕事）
module Simulation
  class ClerkRules
    Verdict = Data.define(:action, :reason) # action は :approve / :reject / :forward

    LIMIT = Banking::Bank::LOAN_LIMIT # 銀行で借りていられる額（返す額の合計）
    FEE = 1.1
    FORWARD_AT = 150

    def initialize(role:)
      @role = role.to_sym
    end

    def review(kase)
      after = kase.owed + (kase.amount * FEE).ceil
      return reject("延滞しているローンがあるので、お貸しできません") if kase.overdue.positive?

      @role == :chief ? chief(kase, after) : teller(kase, after)
    end

    private

    def teller(kase, after)
      return reject("借りすぎです（返す額が #{after} ちゅ〜るになります）") if after > LIMIT * 0.8
      return Verdict.new(:forward, "#{FORWARD_AT} ちゅ〜る以上なので、係長に回します") if kase.amount >= FORWARD_AT

      Verdict.new(:approve, "お給料 #{kase.salary} ちゅ〜るなら返せそうです")
    end

    def chief(kase, after)
      return reject("返す額が #{after} ちゅ〜るになるのは多すぎます") if after > LIMIT * 0.6
      return reject("お給料（#{kase.salary} ちゅ〜る）より多くはお貸しできません") if kase.amount > kase.salary

      Verdict.new(:approve, "係長として決裁しました")
    end

    def reject(reason) = Verdict.new(:reject, reason)
  end
end
