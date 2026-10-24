# 頭（Brain）の答え: 「次に何をするか」。住民はこれを手紙にして、窓口役や郵便屋へ出す。
# 頭は答えを返すだけで、手紙は出さない（決めることと、やることを分ける。Haiku の頭に替えても住民の動きは同じ）
module Simulation
  module Intent
    Work = Data.define                        # しごと場で働いて、給料を頼む（給料日の朝）
    Buy = Data.define(:sku, :quantity)        # ちゅ〜る商店で買う
    Gift = Data.define(:to, :amount, :memo)   # ほかの住民へ振り込む（おすそわけ・助け）
    Rest = Data.define                        # ねむる（気分が少しよくなる）
    AskHelp = Data.define(:amount)            # みんなに「amount ちゅ〜る足りないにゃ」と手紙を出す

    ALL = [ Work, Buy, Gift, Rest, AskHelp ].freeze
  end
end
