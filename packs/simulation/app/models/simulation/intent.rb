# 頭（Brain）の答え: 「次に何をするか」。住民はこれを手紙にして、窓口役や郵便屋へ出す。
# 頭は答えを返すだけで、手紙は出さない（決めることと、やることを分ける。Haiku の頭に替えても住民の動きは同じ）
module Simulation
  module Intent
    Work = Data.define                        # しごと場で働いて、給料を頼む（給料日の朝）
    PayRent = Data.define                     # 大家さんに家賃を払う（家賃の日の朝）
    Eat = Data.define(:sku)                   # ごはん（商店の食べもの）を買う。食べない日は夕方におなかがすく
    Buy = Data.define(:sku, :quantity)        # ちゅ〜る商店で買う（ごはんのほかの、ほしい物）
    Splurge = Data.define(:place)             # 遊び場でお金を使う（またたびバー・ねこカフェ・温泉・宝くじ）
    Gift = Data.define(:to, :amount, :memo)   # ほかの住民へ振り込む（おすそわけ・助け）
    Lend = Data.define(:to, :amount)          # ほかの住民に貸す（借用書が残り、あとで返してもらう）
    Borrow = Data.define(:amount)             # 銀行のちゅ〜るローンで借りる
    Repay = Data.define(:to, :amount)         # 借りたお金を返す（to は住民の名前か Letters::BANK）
    Rest = Data.define                        # ねむる（気分が少しよくなる）
    AskHelp = Data.define(:amount)            # みんなに「amount ちゅ〜る足りないにゃ」と手紙を出す

    ALL = [ Work, PayRent, Eat, Buy, Splurge, Gift, Lend, Borrow, Repay, Rest, AskHelp ].freeze
  end
end
