# 決まりで動く頭。性格（Temperament）の値で確率を変えて、次にすることを決める。
#
#   朝 … 給料日なら働きに行く（Work）
#   昼 … 買いもの（buy の確率。気分がよいほど出かける）
#   夕方 … 知り合いへおすそわけ（gift の確率）。しなければ買いもの
#   夜 … ねむる（Rest）
#   断られた（残高が足りない）… みんなに助けを求める（ask_help の確率）
#   「足りないにゃ」が来た … 助ける（help の確率。使ってよい額のうちで）
#
# 倹約家はいちばん安い物を、ほかの性格は使ってよい額の中から好きな物を選ぶ。
# 衝動買いは、ときどき額を気にせず選ぶ（足りずに断られることがある）
module Simulation
  module Brains
    class Rules
      include Brain

      GIFTS = [ 10, 20, 30 ].freeze

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
        when :morning then Intent::Work.new if tick.payday
        when :noon then shopping(memory)
        when :evening then gift(memory) || shopping(memory)
        when :night then Intent::Rest.new
        end
      end

      def shopping(memory)
        temperament = memory.temperament
        return unless memory.known_money? && chance?(temperament.buy * mood_factor(memory))

        candidates = memory.menu.select { it.price <= memory.budget }
        candidates = memory.menu if temperament.key == :impulsive && chance?(0.3)
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

      def on_reply(memory, reply)
        return if reply.ok || reply.reason != :insufficient || !chance?(memory.temperament.ask_help)

        Intent::AskHelp.new(amount: shortage(memory, reply.request))
      end

      def on_trouble(memory, trouble)
        return if trouble.from == memory.name || !chance?(memory.temperament.help)

        amount = [ trouble.amount, 50 ].min
        return if amount > memory.budget

        Intent::Gift.new(to: trouble.from, amount:, memo: "#{trouble.from}さんへのたすけ")
      end

      # 足りなかった額（わからなければ 30）。10〜100 に丸める
      def shortage(memory, request)
        want = case request
        when Letters::WantPurchase then memory.item(request.sku)&.price.to_i * request.quantity
        when Letters::WantTransfer then request.amount
        else 0
        end
        missing = want - memory.money.to_i
        (missing.positive? ? missing : 30).clamp(10, 100)
      end

      # 気分がよいほど出かける（気分 0 で半分、100 で 1.5 倍）
      def mood_factor(memory) = 0.5 + (memory.mood / 100.0)

      def chance?(probability) = @random.rand < probability
    end
  end
end
