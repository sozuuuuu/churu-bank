# 住民の頭の入口（決まった形）。頭は住民の Ractor の中で作られ、手紙が届くたびに聞かれる。
#
#   decide(memory, letter) → Intent::Work / Buy / Gift / Rest / AskHelp のどれか。何もしないなら nil
#
#   memory … 住民の凍った記憶（Simulation::Memory。所持金の見込み・気分・性格・知り合い・品書き）
#   letter … いま届いた手紙（Letters::Tick 時計の合図 / Letters::Reply 窓口役の返事 / Letters::Trouble ほかの住民の「足りないにゃ」）
#
# 頭は決めるだけ。手紙を出さない・DB に触らない・ほかの住民の中身を見ない（それは住民と窓口役の仕事）。
# だから決まりで動く頭（Brains::Rules）と Haiku で考える頭（Brains::Haiku）を、住民の作りを変えずに差し替えられる
module Simulation
  module Brain
    def decide(memory, letter)
      raise NotImplementedError, "#{self.class.name} は decide(memory, letter) を決めていません"
    end
  end
end
