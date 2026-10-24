# 住民の性格。決まりで動く頭（Brains::Rules）は、この値で「するかどうか」の確率を変える。
#   buy      … 昼・夕方に買いものをする確率
#   gift     … 夕方にほかの住民へおすそわけする確率
#   help     … 「足りないにゃ」の手紙が来たとき、助ける確率
#   ask_help … 断られたとき、みんなに助けを求める確率
#   spend    … 所持金の見込みのうち、一度に使ってよい割合
#   keep     … これだけは残しておきたい額
#   stumble  … 手紙を受け取るたびに、ころぶ（Ractor が倒れる）確率。見張り役を試すための住民だけ
module Simulation
  Temperament = Data.define(:key, :label, :buy, :gift, :help, :ask_help, :spend, :keep, :stumble)

  class Temperament
    # Ractor の中（住民の頭）からも読むので、中身まで凍らせて Ractor で共有できる形にする
    ALL = Ractor.make_shareable({
      frugal: new(key: :frugal, label: "倹約家", buy: 0.15, gift: 0.03, help: 0.3, ask_help: 0.2,
                  spend: 0.25, keep: 150, stumble: 0.0),
      impulsive: new(key: :impulsive, label: "衝動買い", buy: 0.7, gift: 0.1, help: 0.3, ask_help: 0.7,
                     spend: 1.0, keep: 0, stumble: 0.0),
      caring: new(key: :caring, label: "世話焼き", buy: 0.2, gift: 0.4, help: 0.9, ask_help: 0.3,
                  spend: 0.5, keep: 50, stumble: 0.0),
      clumsy: new(key: :clumsy, label: "ころびやすい（見張り役の試験用）", buy: 0.3, gift: 0.1, help: 0.5, ask_help: 0.5,
                  spend: 0.6, keep: 30, stumble: 0.12)
    })

    def self.fetch(key) = ALL.fetch(key.to_sym)

    def self.keys = ALL.keys
  end
end
