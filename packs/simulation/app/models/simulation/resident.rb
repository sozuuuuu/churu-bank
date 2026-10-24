# 住民 1 匹 = Ractor 1 つ（Erlang のプロセスのつもり）。自分の記憶（Memory）を持ち、受け口（Ractor の default_port）に
# 届いた手紙だけで動く。ほかの住民の中身には触らない。銀行や商店にも触らず、役場（メインの Ractor）の窓口役へ手紙で頼む。
#
#   手紙が届く → 記憶を覚えなおす → 頭（Brain）に「次に何をする？」と聞く → 答え（Intent）を手紙にして出す → 役場へ様子を知らせる
#
# :stop が届いたら町を出る（ふつうに終わる）。:crash が届くか、ころびやすい住民がころぶと、例外で倒れる。
# 倒れたら見張り役（Supervisor）が起こし直す。記憶ははじめからで、所持金の見込みは窓口役に聞き直す（Erlang の「let it crash」）
module Simulation
  class Resident
    # 住民の設定。見張り役はこれを持っていて、倒れるたびにここから作り直す。
    # temperament は Temperament の名前、brain は Brains の名前、seed は乱数の種（起こし直すたびに回数を足してずらす）、
    # menu は商店の品書き、places は遊び場（Memory::Place）
    Spec = Data.define(:name, :temperament, :brain, :seed, :friends, :menu, :places) do
      def initialize(places: [], **) = super
    end

    class Stumbled < StandardError; end

    TIMES = Ractor.make_shareable({ morning: "朝", noon: "昼", evening: "夕方", night: "夜" })

    def self.spawn(spec, restarts:, hall:, postman:)
      Ractor.new(spec, restarts, hall, postman, name: "住民 #{spec.name}") do |s, count, town_hall, post|
        Thread.current.report_on_exception = false # 倒れたわけは見張り役が役場へ知らせる
        Resident.new(s, restarts: count, hall: town_hall, postman: post).run
      end
    end

    attr_reader :memory, :last_action

    def initialize(spec, restarts:, hall:, postman:)
      @spec = spec
      @restarts = restarts
      @hall = hall
      @postman = postman
      @random = Random.new(spec.seed + restarts)
      @brain = Brains.fetch(spec.brain).new(random: Random.new(@random.rand(2**31)))
      @memory = Memory.wake(name: spec.name, temperament: Temperament.fetch(spec.temperament), friends: spec.friends,
                            menu: spec.menu, places: spec.places)
      @received = 0 # 受け取った手紙の数（起きてから）
      @sent = 0     # 出した手紙の数
    end

    def name = @spec.name

    def run
      wake_up
      loop do
        letter = Ractor.receive
        break if letter == :stop

        hear(letter)
      end
      @memory = @memory.doing("町を出た")
      report("おやすみ（町を出た）")
    end

    def wake_up
      report(@restarts.zero? ? "起きた" : "見張り役に起こし直してもらった（#{@restarts} 回目）")
      ask(Letters::AskBalance.new(from: name, reply_to: inbox))
    end

    # 手紙を1通聞く（Ractor の外の試験からも呼べる）
    def hear(letter)
      raise Stumbled, "#{name}が手紙につまずいてころんだ" if letter == :crash

      @received += 1
      @memory = @memory.heard(letter)
      stumble!(letter)
      note = answered(letter) if letter.is_a?(Letters::Reply)
      note = "#{letter.from}さんが #{letter.amount} ちゅ〜る貸してくれた（借用書）" if letter.is_a?(Letters::Lent)
      note = act(@brain.decide(@memory, letter)) || note
      report(note) if note || letter.is_a?(Letters::Tick)
    end

    private

    def inbox = Ractor.current.default_port

    def ask(letter)
      @sent += 1
      @hall << letter
    end

    def stumble!(letter)
      return unless letter.is_a?(Letters::Tick) && @random.rand < @memory.temperament.stumble

      raise Stumbled, "#{name}が#{letter.day}日目の#{TIMES.fetch(letter.time)}にころんだ"
    end

    # 頭の答えを手紙にして出す。何をしたかの一言を返す（何もしなければ nil）
    def act(intent)
      case intent
      when Intent::Work
        @memory = @memory.doing("しごと場で働いている")
        ask(Letters::AskSalary.new(from: name, day: @memory.day, reply_to: inbox))
        "働いた。窓口に給料を頼んだ"
      when Intent::PayRent
        ask(Letters::PayRent.new(from: name, day: @memory.day, reply_to: inbox))
        "大家さんに家賃を払いに行った"
      when Intent::Eat
        @memory = @memory.doing("ごはんを買いに行った")
        ask(Letters::WantPurchase.new(from: name, sku: intent.sku, quantity: 1, reply_to: inbox))
        "ごはん（#{@memory.item(intent.sku)&.name || intent.sku}）を買いに行った"
      when Intent::Splurge
        place = @memory.place(intent.place)
        @memory = @memory.doing("#{place&.name || intent.place}にいる")
        ask(Letters::WantFun.new(from: name, place: intent.place, reply_to: inbox))
        "#{place&.name || intent.place}へ遊びに行った"
      when Intent::Borrow
        @memory = @memory.doing("銀行の窓口にいる")
        ask(Letters::WantLoan.new(from: name, amount: intent.amount, reply_to: inbox))
        "銀行に #{intent.amount} ちゅ〜る借りたいと頼んだ"
      when Intent::Lend
        ask(Letters::WantLend.new(from: name, to: intent.to, amount: intent.amount, reply_to: inbox))
        "#{intent.to}さんに #{intent.amount} ちゅ〜る貸すことにした"
      when Intent::Repay
        ask(Letters::WantRepay.new(from: name, to: intent.to, amount: intent.amount, reply_to: inbox))
        "#{intent.to == Letters::BANK ? "銀行" : "#{intent.to}さん"}に #{intent.amount} ちゅ〜る返しに行った"
      when Intent::Buy
        @memory = @memory.doing("ちゅ〜る商店にいる")
        ask(Letters::WantPurchase.new(from: name, sku: intent.sku, quantity: intent.quantity, reply_to: inbox))
        "「#{@memory.item(intent.sku)&.name || intent.sku}」を買いたいと頼んだ"
      when Intent::Gift
        ask(Letters::WantTransfer.new(from: name, to: intent.to, amount: intent.amount, memo: intent.memo, reply_to: inbox))
        "#{intent.to}さんへ #{intent.amount} ちゅ〜る振り込みたいと頼んだ（#{intent.memo}）"
      when Intent::Rest
        @memory = @memory.doing("ねている")
        "ねむった"
      when Intent::AskHelp
        @sent += 1
        @postman << Letters::Broadcast.new(letter: Letters::Trouble.new(from: name, amount: intent.amount), except: name)
        "みんなに「#{intent.amount} ちゅ〜る足りないにゃ」と手紙を出した"
      end
    end

    def answered(reply)
      reply.ok ? "窓口: #{reply.message}" : "窓口に断られた: #{reply.message}"
    end

    def report(note)
      @last_action = note if note
      @hall << Letters::Report.new(name:, state: @memory.state, mood: @memory.mood, money: @memory.money,
                                   last_action: @last_action, received: @received, sent: @sent)
    end
  end
end
