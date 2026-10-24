# 住民の記憶。住民の Ractor の中だけにあって、ほかの住民からは見えない（Erlang のプロセスの状態と同じ）。
# 凍った Data なので、手紙を聞くたびに with で新しい記憶を作る（heard）。頭（Brain）にはこれをそのまま見せる。
#   money … 所持金の見込み（窓口役の返事で知った残高。はじめは nil = まだ知らない）
#   mood  … 気分（0〜100）
#   day / time … 時計役の合図で知った、いまの日と時間
#   state … いましていること（画面に出す）
#   friends … 知り合いの住民の名前、menu … 商店の品書き（Memory::MenuItem）、places … 遊び場（Memory::Place）
#   debts … 借金の帳面（{ 貸した住民の名前 か Letters::BANK => まだ返していない額 }。窓口役の返事で書きなおす）
#   ate_day … 最後にごはんを食べた日（夕方までに食べていないと、おなかがすいて気分が下がる）
module Simulation
  Memory = Data.define(:name, :temperament, :friends, :menu, :places, :money, :mood, :day, :time, :state, :debts,
                       :ate_day)

  class Memory
    # food: ごはんになる物（ちゅ〜る）
    MenuItem = Data.define(:sku, :name, :price, :food) do
      def initialize(food: false, **) = super
    end
    Place = Data.define(:key, :name, :price)

    STATES = Ractor.make_shareable({ morning: "朝のしたく", noon: "ぶらぶら", evening: "夕方のひととき", night: "ねている" })
    HUNGRY = -12 # 夕方までに食べていないとき

    def self.wake(name:, temperament:, friends:, menu:, places: [], mood: 60)
      new(name:, temperament:, friends:, menu:, places:, money: nil, mood:, day: nil, time: nil, state: "起きた",
          debts: {}, ate_day: nil)
    end

    # 手紙を聞いて覚えなおす（気分・所持金の見込み・時間・借金・ごはん）
    def heard(letter)
      case letter
      when Letters::Tick
        mood_change = letter.time == :night ? 8 : -2
        mood_change += HUNGRY if letter.time == :evening && !ate_today?(letter.day)
        with(day: letter.day, time: letter.time, state: STATES.fetch(letter.time), mood: clamp(mood + mood_change))
      when Letters::Reply then heard_reply(letter)
      when Letters::Lent then with(mood: clamp(mood + 6)) # 貸してもらえた
      else
        self
      end
    end

    def doing(state) = with(state:)

    def known_money? = !money.nil?

    def ate_today?(today = day) = !ate_day.nil? && ate_day == today

    def hungry? = time == :evening && !ate_today?

    # 借金の合計・銀行の分・住民の分
    def total_debt = debts.values.sum
    def bank_debt = debts.fetch(Letters::BANK, 0)
    def friend_debts = debts.except(Letters::BANK)

    # 一度に使ってよい額（性格の「使う割合」と「残しておきたい額」から）
    def budget
      return 0 unless known_money?

      [ (money * temperament.spend).floor, money - temperament.keep ].min.clamp(0, money)
    end

    def item(sku) = menu.find { it.sku == sku }

    def food = menu.select(&:food)

    def place(key) = places.find { it.key == key }

    private

    def heard_reply(reply)
      changed = reply.balance.nil? ? self : with(money: reply.balance)
      changed = changed.with(debts: reply.debts) unless reply.debts.nil?
      changed = changed.with(ate_day: day) if reply.ok && meal?(reply.request)
      changed.with(mood: clamp(mood + (reply.ok ? happiness(reply.request) : -12)))
    end

    def meal?(request) = request.is_a?(Letters::WantPurchase) && item(request.sku)&.food

    def happiness(request)
      case request
      when Letters::AskSalary then 15
      when Letters::WantFun then 20
      when Letters::WantPurchase then 10
      when Letters::WantTransfer, Letters::WantLend then 6
      when Letters::WantRepay then 4
      when Letters::WantLoan then -4 # 借りられたけれど、借金は気が重い
      else 0
      end
    end

    def clamp(value) = value.clamp(0, 100)
  end
end
