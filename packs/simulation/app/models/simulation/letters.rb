# shareable_constant_value: literal

# 手紙: Ractor のあいだで送るもの。どれも Data（凍っている）で、中身は数・記号・凍った文字・Ractor::Port だけにするので、
# Ractor をまたいでも写しを作らずにそのまま渡せる（Ractor.shareable?）。
#
#   時計役 ──Tick──▶ 郵便屋 ──▶ 住民みんな        （時計役は役場にも Tick を送る）
#   住民 ──Ask…/Want…/PayRent──▶ 役場（メインの Ractor の窓口役）──Reply──▶ 住民の受け口（reply_to）
#   住民 ──Broadcast(Trouble)──▶ 郵便屋 ──▶ ほかの住民
#   役場 ──Deliver(Lent)──▶ 郵便屋 ──▶ 借りた住民      （貸した住民の振込が通ったとき）
#   郵便屋 ──Copy──▶ 役場（住民どうしの手紙の写し。画面の「手紙の流れ」へ）
#   住民 ──Report──▶ 役場（画面へ）、見張り役 ──Restarted──▶ 役場
module Simulation
  module Letters
    # 借りた相手が銀行のときの名前（借金の帳面 Reply#debts と WantRepay#to で使う）
    BANK = "銀行"

    # 時計役 → 住民・役場。time は :morning（朝）/ :noon（昼）/ :evening（夕方）/ :night（夜）。
    # payday は給料日の朝、rent_day は家賃の日の朝
    Tick = Data.define(:day, :time, :payday, :rent_day) do
      def initialize(rent_day: false, **) = super
    end

    # ---- 住民 → 窓口役（メインの Ractor）。reply_to は住民の受け口（Ractor::Port）。返事は Reply ----
    AskBalance = Data.define(:from, :reply_to)                       # 残高を教えて
    AskSalary = Data.define(:from, :day, :reply_to)                  # 働いたので給料を払って（給料日だけ）
    WantTransfer = Data.define(:from, :to, :amount, :memo, :reply_to) # ほかの住民へ振り込みたい
    WantPurchase = Data.define(:from, :sku, :quantity, :reply_to)    # ちゅ〜る商店で買いたい
    PayRent = Data.define(:from, :day, :reply_to)                    # 家賃を払う（家賃の日だけ）
    WantFun = Data.define(:from, :place, :reply_to)                  # 遊び場でお金を使いたい（place は Roster::PLACES の名前）
    WantLoan = Data.define(:from, :amount, :reply_to)                # 銀行（ちゅ〜るローン）で借りたい
    WantLend = Data.define(:from, :to, :amount, :reply_to)           # ほかの住民に貸したい（借用書を残す）
    WantRepay = Data.define(:from, :to, :amount, :reply_to)          # 借りたお金を返したい（to は住民の名前か BANK）
    REQUESTS = [ AskBalance, AskSalary, WantTransfer, WantPurchase, PayRent, WantFun, WantLoan, WantLend, WantRepay ].freeze

    # 窓口役 → 住民。reason は断ったわけ（:insufficient 残高が足りない / :sold_out 売り切れ / :not_payday 給料日・家賃の日ではない /
    # :loan_limit もう借りられない / :refused そのほか）。
    # debts はその住民の借金の帳面（{ 貸した住民の名前 か BANK => まだ返していない額 }）。起こし直された住民も、これで思い出す
    Reply = Data.define(:request, :ok, :message, :balance, :reason, :debts) do
      def initialize(reason: nil, balance: nil, debts: nil, **) = super
    end

    # 住民 → ほかの住民（郵便屋が配る）。「amount ちゅ〜る足りないにゃ」
    Trouble = Data.define(:from, :amount)
    # 役場 → 借りた住民（郵便屋が配る）。「from さんが amount ちゅ〜る貸してくれた」
    Lent = Data.define(:from, :amount)

    # ---- 郵便屋へ ----
    Register = Data.define(:name, :port)              # この名前の住民の受け口は port（起こし直すたびに新しくなる）
    Broadcast = Data.define(:letter, :except) do      # みんなへ（except の名前の住民を除く）
      def initialize(except: nil, **) = super
    end
    Deliver = Data.define(:to, :letter)               # 名前の住民1匹へ

    # 郵便屋 → 役場: 住民どうしの手紙の写し（時計の合図は写さない）。to は名前か "みんな"
    Copy = Data.define(:from, :to, :letter)

    # 住民 → 役場（画面の「住民の様子」へ）。received / sent は、受け取った・出した手紙の数（起きてから）
    Report = Data.define(:name, :state, :mood, :money, :last_action, :received, :sent) do
      def initialize(received: 0, sent: 0, **) = super
    end
    # 見張り役 → 役場。count は起こし直した回数、reason は倒れたわけ
    Restarted = Data.define(:name, :count, :reason)

    # 見張り役へ: 名前の住民に手紙を渡してもらう（試験で :crash を渡して倒すときなど）
    Poke = Data.define(:name, :letter)
    # 時計役へ: 1日を何秒にするか
    Speed = Data.define(:seconds_per_day)
  end
end
