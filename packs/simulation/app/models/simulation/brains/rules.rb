# 決まりで動く頭。性格（Temperament）の値で確率を変えて、次にすることを決める。
#
#   朝 … 給料日なら働きに行く（Work）、家賃の日なら家賃を払う（PayRent）
#   昼 … ごはんを買う（Eat。食べないと夕方におなかがすく）
#   夕方 … 借金があれば返す（repay の確率の半分）→ 遊び場（splurge）→ おすそわけ（gift）→ ほしい物（buy）のどれか
#   夜 … ねむる（Rest）
#   お給料が入った … 借金を返す（repay の確率。いちばん多い借金から、使ってよい額で）
#   断られた（残高が足りない）… 銀行で借りる（borrow の確率。家賃・ごはんなら借りやすい）か、みんなに助けを求める（ask_help）
#   「足りないにゃ」が来た … 助ける（help の確率）。貸す（lend の確率）か、あげる
#
# 倹約家はいちばん安い物を、ほかの性格は使ってよい額の中から好きな物を選ぶ。
# 衝動買いは、ときどき額を気にせず選ぶ（足りずに断られて、借りることになる）
module Simulation
  module Brains
    class Rules
      include Brain

      GIFTS = [ 10, 20, 30 ].freeze
      LOAN_LIMIT = Banking::Bank::LOAN_LIMIT # 銀行で借りていられる額（返す額の合計）
      LOAN_FEE = 1.1                         # 返す額 ≒ 借りた額 × 1.1

      # random を渡すと、同じ種なら同じように決める（試験用）
      def initialize(random: Random.new)
        @random = random
      end

      def decide(memory, letter)
        case letter
        when Letters::Tick then on_tick(memory, letter)
        when Letters::Reply then on_reply(memory, letter)
        when Letters::Trouble then on_trouble(memory, letter)
        end
      end

      private

      def on_tick(memory, tick)
        case tick.time
        when :morning
          return Intent::Work.new if tick.payday

          Intent::PayRent.new if tick.rent_day
        when :noon then eat(memory)
        when :evening then evening(memory)
        when :night then Intent::Rest.new
        end
      end

      def eat(memory)
        return if !memory.known_money? || memory.ate_today? || memory.food.empty?

        food = memory.temperament.key == :frugal ? memory.food.min_by(&:price) : memory.food.sample(random: @random)
        Intent::Eat.new(sku: food.sku)
      end

      def evening(memory)
        return unless memory.known_money?

        repay(memory, chance: memory.temperament.repay / 2) || splurge(memory) || gift(memory) || shopping(memory)
      end

      def splurge(memory)
        temperament = memory.temperament
        return if memory.places.empty? || !chance?(temperament.splurge * mood_factor(memory))

        candidates = memory.places.select { it.price <= memory.budget }
        candidates = memory.places if temperament.key == :impulsive && chance?(0.4)
        return if candidates.empty?

        Intent::Splurge.new(place: candidates.sample(random: @random).key)
      end

      def shopping(memory)
        temperament = memory.temperament
        return unless chance?(temperament.buy * mood_factor(memory))

        wants = memory.menu.reject(&:food)
        candidates = wants.select { it.price <= memory.budget }
        candidates = wants if temperament.key == :impulsive && chance?(0.3)
        return if candidates.empty?

        item = temperament.key == :frugal ? candidates.min_by(&:price) : candidates.sample(random: @random)
        Intent::Buy.new(sku: item.sku, quantity: 1)
      end

      def gift(memory)
        return if memory.friends.empty? || !chance?(memory.temperament.gift)

        amount = GIFTS.select { it <= memory.budget }.sample(random: @random)
        return unless amount

        Intent::Gift.new(to: memory.friends.sample(random: @random), amount:, memo: "おすそわけ")
      end

      # 借金を返す。いちばん多い借金から、使ってよい額（なければ所持金の半分）で
      def repay(memory, chance: memory.temperament.repay)
        return if memory.debts.empty? || !chance?(chance)

        to, owed = memory.debts.max_by { |_name, amount| amount }
        amount = [ owed, [ memory.budget, memory.money.to_i / 2 ].max ].min
        Intent::Repay.new(to:, amount:) if amount.positive?
      end

      def on_reply(memory, reply)
        return repay(memory) if reply.ok && reply.request.is_a?(Letters::AskSalary)
        return if reply.ok || reply.reason != :insufficient

        need = shortage(memory, reply.request)
        necessity = reply.request.is_a?(Letters::PayRent) ||
                    (reply.request.is_a?(Letters::WantPurchase) && memory.item(reply.request.sku)&.food)
        borrow_chance = memory.temperament.borrow + (necessity ? 0.4 : 0)
        if can_borrow?(memory, need) && chance?(borrow_chance)
          Intent::Borrow.new(amount: need)
        elsif chance?(memory.temperament.ask_help)
          Intent::AskHelp.new(amount: need.clamp(10, 100))
        end
      end

      def can_borrow?(memory, amount) = memory.bank_debt + (amount * LOAN_FEE).ceil <= LOAN_LIMIT

      def on_trouble(memory, trouble)
        return if trouble.from == memory.name || !chance?(memory.temperament.help)

        amount = [ trouble.amount, 50 ].min
        return if amount > memory.budget

        if chance?(memory.temperament.lend)
          Intent::Lend.new(to: trouble.from, amount:)
        else
          Intent::Gift.new(to: trouble.from, amount:, memo: "#{trouble.from}さんへのたすけ")
        end
      end

      # 足りなかった額。10 ちゅ〜る単位に切り上げて 50〜300（わからなければ 50）
      def shortage(memory, request)
        want = case request
        when Letters::WantPurchase then memory.item(request.sku)&.price.to_i * request.quantity
        when Letters::WantFun then memory.place(request.place)&.price.to_i
        when Letters::WantTransfer, Letters::WantLend, Letters::WantRepay then request.amount
        else 0
        end
        missing = want - memory.money.to_i
        missing = 50 unless missing.positive?
        (missing.to_f / 10).ceil.*(10).clamp(50, 300)
      end

      # 気分がよいほど出かける（気分 0 で半分、100 で 1.5 倍）
      def mood_factor(memory) = 0.5 + (memory.mood / 100.0)

      def chance?(probability) = @random.rand < probability
    end
  end
end
