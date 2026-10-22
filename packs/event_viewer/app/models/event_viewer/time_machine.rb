# タイムマシン: 口座のストリーム（Account$<口座番号>）の出来事を順に足し合わせて、どの時点の残高と状態も作り直す（読むだけ）。
# 「いまの残高」も、読み取りモデル（accounts.balance）を見ずに、はじめの出来事から足していった結果と同じになる。
#
# 並べ方は Banking::Statement と同じ2通り:
#   - :as_of … 起算日（valid_at）の順。「本当はいつのことか」。3日前の分としてあとから入金したら、3日前のところに入る
#   - :as_at … 記帳日（timestamp）の順。「銀行がいつ知ったか」。あとから入金した分は、記帳した日のところに入る
module EventViewer
  class TimeMachine
    BASES = { as_of: "起算日の順（本当はいつのことか）", as_at: "記帳日の順（銀行がいつ知ったか）" }.freeze
    STATUSES = {
      Banking::Events::AccountOpened => "利用中", Banking::Events::AccountFrozen => "凍結中",
      Banking::Events::AccountUnfrozen => "利用中", Banking::Events::AccountClosed => "解約済み"
    }.freeze

    # position は 1 から。delta は残高の増減（お金が動かない出来事は 0）。balance / status はこの出来事を足したあと
    Line = Data.define(:position, :event, :delta, :balance, :status, :at) do
      def money? = !delta.zero?
    end

    attr_reader :number, :basis

    def initialize(number, basis: :as_of, event_store: Rails.configuration.event_store)
      @number = number
      @basis = BASES.key?(basis&.to_sym) ? basis.to_sym : :as_of
      @event_store = event_store
    end

    def lines
      @lines ||= begin
        balance = 0
        status = "未開設"
        events.each_with_index.map do |event, i|
          delta = Banking::Events.balance_delta(event) || 0
          balance += delta
          status = STATUSES.fetch(event.class, status)
          Line.new(position: i + 1, event:, delta:, balance:, status:, at: time_of(event))
        end
      end
    end

    # position 番目の出来事まで足したときの残高（0 なら、まだ何も起きていない）
    def balance_at(position) = position.zero? ? 0 : lines.fetch(position - 1).balance

    def balance = lines.last&.balance || 0

    # 起算日と記帳日がずれている出来事（あとから過去の日付で記帳した入金など）
    def backdated?(event) = event.valid_at.to_date != event.timestamp.to_date

    private

    def events
      reader = @event_store.read.stream("Account$#{@number}")
      (@basis == :as_at ? reader.as_at : reader.as_of).to_a
    end

    def time_of(event) = @basis == :as_at ? event.timestamp : event.valid_at
  end
end
