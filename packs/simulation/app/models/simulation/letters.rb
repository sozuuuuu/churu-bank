# shareable_constant_value: literal

# 手紙: Ractor のあいだで送るもの。どれも Data（凍っている）で、中身は数・記号・凍った文字・Ractor::Port だけにするので、
# Ractor をまたいでも写しを作らずにそのまま渡せる（Ractor.shareable?）。
#
#   時計役 ──Tick──▶ 郵便屋 ──▶ 住民みんな        （時計役は役場にも Tick を送る）
#   住民 ──Ask…/Want…──▶ 役場（メインの Ractor の窓口役）──Reply──▶ 住民の受け口（reply_to）
#   住民 ──Broadcast(Trouble)──▶ 郵便屋 ──▶ ほかの住民
#   住民 ──Report──▶ 役場（画面へ）、見張り役 ──Restarted──▶ 役場
module Simulation
  module Letters
    # 時計役 → 住民・役場。time は :morning（朝）/ :noon（昼）/ :evening（夕方）/ :night（夜）
    Tick = Data.define(:day, :time, :payday)

    # ---- 住民 → 窓口役（メインの Ractor）。reply_to は住民の受け口（Ractor::Port）。返事は Reply ----
    AskBalance = Data.define(:from, :reply_to)                       # 残高を教えて
    AskSalary = Data.define(:from, :day, :reply_to)                  # 働いたので給料を払って（給料日だけ）
    WantTransfer = Data.define(:from, :to, :amount, :memo, :reply_to) # ほかの住民へ振り込みたい
    WantPurchase = Data.define(:from, :sku, :quantity, :reply_to)    # ちゅ〜る商店で買いたい
    REQUESTS = [ AskBalance, AskSalary, WantTransfer, WantPurchase ].freeze

    # 窓口役 → 住民。reason は断ったわけ（:insufficient 残高が足りない / :sold_out 売り切れ / :not_payday / :refused そのほか）
    Reply = Data.define(:request, :ok, :message, :balance, :reason) do
      def initialize(reason: nil, balance: nil, **) = super
    end

    # 住民 → ほかの住民（郵便屋が配る）。「amount ちゅ〜る足りないにゃ」
    Trouble = Data.define(:from, :amount)

    # ---- 郵便屋へ ----
    Register = Data.define(:name, :port)              # この名前の住民の受け口は port（起こし直すたびに新しくなる）
    Broadcast = Data.define(:letter, :except) do      # みんなへ（except の名前の住民を除く）
      def initialize(except: nil, **) = super
    end

    # 住民 → 役場（画面の「住民の様子」へ）
    Report = Data.define(:name, :state, :mood, :money, :last_action)
    # 見張り役 → 役場。count は起こし直した回数、reason は倒れたわけ
    Restarted = Data.define(:name, :count, :reason)

    # 見張り役へ: 名前の住民に手紙を渡してもらう（試験で :crash を渡して倒すときなど）
    Poke = Data.define(:name, :letter)
    # 時計役へ: 1日を何秒にするか
    Speed = Data.define(:seconds_per_day)
  end
end
