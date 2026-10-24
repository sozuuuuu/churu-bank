# 住民の性格。決まりで動く頭（Brains::Rules）は、この値で「するかどうか」の確率を変える。
#   buy      … 夕方にほしい物を買う確率
#   splurge  … 夕方に遊び場（またたびバー・ねこカフェ・温泉・宝くじ）でお金を使う確率
#   gift     … 夕方にほかの住民へおすそわけする確率
#   help     … 「足りないにゃ」の手紙が来たとき、助ける確率
#   lend     … 助けるとき、あげるのではなく貸す確率（借用書が残る）
#   ask_help … 断られたとき、みんなに助けを求める確率
#   borrow   … 断られたとき、銀行のちゅ〜るローンで借りる確率（家賃・ごはんのときは、もっと借りやすい）
#   repay    … お給料が入ったとき、借金を返す確率（低いと、ずるずる借りたまま）
#   spend    … 所持金の見込みのうち、一度に使ってよい割合
#   keep     … これだけは残しておきたい額
#   salary   … 給料日のお給料
#   stumble  … 手紙を受け取るたびに、ころぶ（Ractor が倒れる）確率。見張り役を試すための住民だけ
module Simulation
  Temperament = Data.define(:key, :label, :buy, :splurge, :gift, :help, :lend, :ask_help, :borrow, :repay, :spend,
                            :keep, :salary, :stumble)

  class Temperament
    # Ractor の中（住民の頭）からも読むので、中身まで凍らせて Ractor で共有できる形にする
    ALL = Ractor.make_shareable({
      frugal: new(key: :frugal, label: "倹約家", buy: 0.1, splurge: 0.05, gift: 0.03, help: 0.3, lend: 0.8,
                  ask_help: 0.2, borrow: 0.1, repay: 0.95, spend: 0.25, keep: 150, salary: 170, stumble: 0.0),
      impulsive: new(key: :impulsive, label: "衝動買い", buy: 0.5, splurge: 0.6, gift: 0.1, help: 0.3, lend: 0.2,
                     ask_help: 0.4, borrow: 0.8, repay: 0.35, spend: 1.0, keep: 0, salary: 200, stumble: 0.0),
      caring: new(key: :caring, label: "世話焼き", buy: 0.15, splurge: 0.2, gift: 0.3, help: 0.9, lend: 0.6,
                  ask_help: 0.3, borrow: 0.3, repay: 0.9, spend: 0.5, keep: 50, salary: 160, stumble: 0.0),
      clumsy: new(key: :clumsy, label: "ころびやすい（見張り役の試験用）", buy: 0.25, splurge: 0.3, gift: 0.1, help: 0.5,
                  lend: 0.4, ask_help: 0.5, borrow: 0.5, repay: 0.6, spend: 0.6, keep: 30, salary: 170, stumble: 0.12)
    })

    def self.fetch(key) = ALL.fetch(key.to_sym)

    def self.keys = ALL.keys
  end
end
