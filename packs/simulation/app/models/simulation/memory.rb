# 住民の記憶。住民の Ractor の中だけにあって、ほかの住民からは見えない（Erlang のプロセスの状態と同じ）。
# 凍った Data なので、手紙を聞くたびに with で新しい記憶を作る（heard）。頭（Brain）にはこれをそのまま見せる。
#   money … 所持金の見込み（窓口役の返事で知った残高。はじめは nil = まだ知らない）
#   mood  … 気分（0〜100）
#   day / time … 時計役の合図で知った、いまの日と時間
#   state … いましていること（画面に出す）
#   friends … 知り合いの住民の名前、menu … 商店の品書き（Memory::MenuItem）
module Simulation
  Memory = Data.define(:name, :temperament, :friends, :menu, :money, :mood, :day, :time, :state)

  class Memory
    MenuItem = Data.define(:sku, :name, :price)

    STATES = Ractor.make_shareable({ morning: "朝のしたく", noon: "ぶらぶら", evening: "夕方のひととき", night: "ねている" })

    def self.wake(name:, temperament:, friends:, menu:, mood: 60)
      new(name:, temperament:, friends:, menu:, money: nil, mood:, day: nil, time: nil, state: "起きた")
    end

    # 手紙を聞いて覚えなおす（気分・所持金の見込み・時間）
    def heard(letter)
      case letter
      when Letters::Tick
        mood_change = letter.time == :night ? 8 : -2
        with(day: letter.day, time: letter.time, state: STATES.fetch(letter.time), mood: clamp(mood + mood_change))
      when Letters::Reply
        changed = letter.balance.nil? ? self : with(money: letter.balance)
        changed.with(mood: clamp(mood + (letter.ok ? happiness(letter.request) : -12)))
      else
        self
      end
    end

    def doing(state) = with(state:)

    def known_money? = !money.nil?

    # 一度に使ってよい額（性格の「使う割合」と「残しておきたい額」から）
    def budget
      return 0 unless known_money?

      [ (money * temperament.spend).floor, money - temperament.keep ].min.clamp(0, money)
    end

    def item(sku) = menu.find { it.sku == sku }

    private

    def happiness(request)
      case request
      when Letters::AskSalary then 15
      when Letters::WantPurchase then 10
      when Letters::WantTransfer then 6
      else 0
      end
    end

    def clamp(value) = value.clamp(0, 100)
  end
end
