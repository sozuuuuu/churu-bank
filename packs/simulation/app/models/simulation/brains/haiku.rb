# Haiku（Claude）で考える頭の入り口。今回は API を呼ばない（キーをまだ使わない）。形だけ用意してある。
#
# ここに入るもの:
#   1. prompt(memory, letter) … 記憶と届いた手紙を、Haiku に渡すことばにする（下に作ってある）
#   2. 考える係（think）に prompt を渡して、答えの JSON を受け取る ← ここに API の呼び出しが入る
#   3. parse(answer) … 答えの JSON を Intent にする（下に作ってある。形がおかしければ nil = 何もしない）
#
# think は `->(prompt) { 答えの文字列 }` の形で外から渡す。渡さなければ、決まりで動く頭（Rules）にまかせる。
# 気をつけること: 住民の頭は Ractor の中で動くので、HTTP の部品（Net::HTTP・OpenSSL・SDK）が Ractor の中で使えるかを先に確かめる。
# 使えなければ、住民は役場（メインの Ractor）の「考える係」へ手紙で頼み、返事の手紙で決める（窓口役と同じ形）。
# そのときは、考えているあいだも住民は手紙を受け取れる（返事が来るまでは前の予定のまま動く）ようにする
module Simulation
  module Brains
    class Haiku
      include Brain

      MODEL = "claude-haiku-5-5".freeze
      TIMES = { morning: "朝", noon: "昼", evening: "夕方", night: "夜" }.freeze

      def initialize(think: nil, random: Random.new)
        @think = think
        @fallback = Rules.new(random:)
      end

      def decide(memory, letter)
        return @fallback.decide(memory, letter) unless @think

        parse(@think.call(prompt(memory, letter)), memory)
      end

      # Haiku に渡すことば。答えは JSON 1つだけにしてもらう
      def prompt(memory, letter)
        <<~PROMPT
          あなたは、ねこ町に住むねこの「#{memory.name}」です。性格は「#{memory.temperament.label}」。
          いまは #{memory.day || "?"} 日目の#{TIMES[memory.time] || "?"}。気分は #{memory.mood}/100、所持金の見込みは #{memory.money || "わからない"} ちゅ〜る。
          きょうのごはん: #{memory.ate_today? ? "食べた" : "まだ"}。借金: #{debts(memory)}
          知り合い: #{memory.friends.join("、")}
          商店の品書き: #{memory.menu.map { "#{it.sku}（#{it.name}、#{it.price} ちゅ〜る#{"、ごはん" if it.food}）" }.join("、")}
          遊び場: #{memory.places.map { "#{it.key}（#{it.name}、#{it.price} ちゅ〜る）" }.join("、")}
          届いた手紙: #{describe(letter)}

          次にすることを、JSON 1つだけで答えてください（ほかの文は書かない）:
            {"do":"work"} 働いて給料をもらう（給料日の朝だけ）
            {"do":"rent"} 家賃を払う（家賃の日の朝だけ）
            {"do":"eat","sku":"…"} ごはんを買う（食べないと夕方におなかがすく）
            {"do":"buy","sku":"…","quantity":1} 商店で買う
            {"do":"fun","place":"…"} 遊び場でお金を使う
            {"do":"gift","to":"知り合いの名前","amount":数,"memo":"…"} 振り込む
            {"do":"lend","to":"知り合いの名前","amount":数} 貸す（借用書が残る）
            {"do":"borrow","amount":数} 銀行のちゅ〜るローンで借りる（手数料 10%）
            {"do":"repay","to":"貸してくれた名前 か 銀行","amount":数} 借りたお金を返す
            {"do":"rest"} ねむる
            {"do":"ask_help","amount":数} みんなに助けを求める
            {"do":"nothing"} 何もしない
        PROMPT
      end

      # 答えの JSON → Intent。知らないこと・品書きにない商品・知り合いでない相手は、何もしない（nil）
      def parse(answer, memory)
        data = JSON.parse(answer.to_s[/\{.*\}/m] || "{}")
        case data["do"]
        when "work" then Intent::Work.new
        when "rent" then Intent::PayRent.new
        when "rest" then Intent::Rest.new
        when "eat" then Intent::Eat.new(sku: data["sku"]) if memory.item(data["sku"])&.food
        when "fun" then Intent::Splurge.new(place: data["place"]) if memory.place(data["place"])
        when "borrow" then Intent::Borrow.new(amount: Integer(data["amount"]))
        when "lend"
          Intent::Lend.new(to: data["to"], amount: Integer(data["amount"])) if memory.friends.include?(data["to"])
        when "repay"
          Intent::Repay.new(to: data["to"], amount: Integer(data["amount"])) if memory.debts.key?(data["to"])
        when "buy"
          Intent::Buy.new(sku: data["sku"], quantity: Integer(data.fetch("quantity", 1))) if memory.item(data["sku"])
        when "gift"
          if memory.friends.include?(data["to"])
            Intent::Gift.new(to: data["to"], amount: Integer(data["amount"]), memo: data["memo"].to_s[0, 20])
          end
        when "ask_help" then Intent::AskHelp.new(amount: Integer(data["amount"]))
        end
      rescue JSON::ParserError, ArgumentError, TypeError
        nil
      end

      private

      def describe(letter)
        case letter
        when Letters::Tick then "時計の合図（#{TIMES[letter.time]}#{"・給料日" if letter.payday}）"
        when Letters::Reply then "窓口の返事「#{letter.message}」"
        when Letters::Trouble then "#{letter.from}さんから「#{letter.amount} ちゅ〜る足りないにゃ」"
        when Letters::Lent then "#{letter.from}さんが #{letter.amount} ちゅ〜る貸してくれた"
        else letter.to_s
        end
      end

      def debts(memory)
        return "なし" if memory.debts.empty?

        memory.debts.map { |name, amount| "#{name}に #{amount} ちゅ〜る" }.join("、")
      end
    end
  end
end
