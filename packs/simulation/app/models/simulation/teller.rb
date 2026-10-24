# 窓口役（メインの Ractor）: 住民の手紙（Letters::AskBalance / AskSalary / WantTransfer / WantPurchase）を確かめて、
# これまでどおり銀行（Banking::Bank）と商店（Shop::Store）の公開の入口で書く。ActiveRecord もイベントストアも、ここ（メイン）でだけ使う。
#
# 確かめること: 町の住民か・相手も住民か（自分あては不可）・金額の範囲・給料日か（同じ日に2回は払わない）・売り切れか・
# 残高が足りるか（銀行のドライランで。足りなければ :insufficient で断る）。断ったら返事（Letters::Reply）でわけを伝える。
#
# 書いた出来事の metadata には resident（住民の名前）を付ける（印）。だれがは actor（住民の利用者 customer:<id>。給料は town-payroll）。
# 印は RES の with_metadata で付けるので、銀行・商店の側は住民のことを知らないまま。
# 振込の後半（入金）や商店の引き当ては、いつもどおり Solid Queue のジョブが続ける（そちらには印は付かない。つながりは correlation_id でたどれる）
module Simulation
  class Teller
    SALARY = 120
    PAYROLL_ACTOR = "town-payroll".freeze
    MAX_TRANSFER = 100
    MAX_QUANTITY = 3

    attr_accessor :today # いちばん新しい時計の合図（Letters::Tick）

    # residents: { 名前 => ResidentStatus }
    def initialize(residents:, employer_account:, event_store: Rails.configuration.event_store)
      @residents = residents
      @employer_account = employer_account
      @event_store = event_store
    end

    # 手紙1通に、返事（Letters::Reply）を1通返す
    def handle(letter)
      resident = @residents[letter.from]
      return refuse(letter, "町の住民ではありません") unless resident

      case letter
      when Letters::AskBalance then answer(letter, "残高は #{balance(resident)} ちゅ〜るです", balance(resident))
      when Letters::AskSalary then pay_salary(letter, resident)
      when Letters::WantTransfer then transfer(letter, resident)
      when Letters::WantPurchase then purchase(letter, resident)
      else refuse(letter, "その手紙はあつかっていません")
      end
    rescue Banking::InsufficientFunds => e
      refuse(letter, e.message, reason: :insufficient, balance: resident && balance(resident))
    rescue Banking::Error, Shop::Error, ArgumentError => e
      refuse(letter, e.message, balance: resident && balance(resident))
    end

    private

    def pay_salary(letter, resident)
      unless today&.payday && today.day == letter.day
        return refuse(letter, "きょうは給料日ではありません", reason: :not_payday, balance: balance(resident))
      end
      if resident.paid_day == letter.day
        return refuse(letter, "#{letter.day} 日目の給料はもう払いました", reason: :not_payday, balance: balance(resident))
      end

      before = balance(resident)
      mark(resident) do
        bank(PAYROLL_ACTOR).transfer(@employer_account, resident.account_number, SALARY,
                                     memo: "ねこ町のお給料（#{letter.day} 日目）", holdable: false)
      end
      resident.update!(paid_day: letter.day)
      # 入金はこのあと振込の係（Solid Queue）がするので、見込みとして足しておく
      answer(letter, "お給料 #{SALARY} ちゅ〜るを振り込みました", before + SALARY)
    end

    def transfer(letter, resident)
      to = @residents[letter.to]
      return refuse(letter, "#{letter.to}さんは町の住民ではありません") unless to
      return refuse(letter, "自分には振り込めません") if to == resident
      unless letter.amount.is_a?(Integer) && letter.amount.between?(1, MAX_TRANSFER)
        return refuse(letter, "振込は 1〜#{MAX_TRANSFER} ちゅ〜るまでです", balance: balance(resident))
      end

      bank = bank(resident.customer.actor)
      bank.transfer(resident.account_number, to.account_number, letter.amount, memo: letter.memo, dry_run: true)
      outcome = mark(resident) do
        bank.transfer(resident.account_number, to.account_number, letter.amount, memo: letter.memo)
      end
      answer(letter, "#{to.name}さんへ #{letter.amount} ちゅ〜る振り込みました", outcome.balance_after)
    end

    def purchase(letter, resident)
      product = ::ShopProduct.find_by(sku: letter.sku)
      return refuse(letter, "その商品はありません", balance: balance(resident)) unless product
      unless letter.quantity.is_a?(Integer) && letter.quantity.between?(1, MAX_QUANTITY)
        return refuse(letter, "一度に買えるのは #{MAX_QUANTITY} こまでです", balance: balance(resident))
      end
      if product.stock < letter.quantity
        return refuse(letter, "「#{product.name}」は売り切れです", reason: :sold_out, balance: balance(resident))
      end

      store = Shop::Store.new(actor: resident.customer.actor, event_store: @event_store)
      items = { product.sku => letter.quantity }
      store.place_order(order_id: SecureRandom.uuid, buyer_account: resident.account_number, items:, dry_run: true)
      outcome = mark(resident) do
        store.place_order(order_id: SecureRandom.uuid, buyer_account: resident.account_number, items:)
      end
      return refuse(letter, "支払いができませんでした", balance: balance(resident)) unless outcome.payment

      answer(letter, "「#{product.name}」を #{letter.quantity} こ買いました（#{outcome.total} ちゅ〜る）",
             outcome.payment.balance_after)
    end

    # この中で書いた出来事に、住民の印を付ける
    def mark(resident, &) = @event_store.with_metadata(resident: resident.name, &)

    def bank(actor) = Banking::Bank.new(actor:, event_store: @event_store)

    def balance(resident) = bank(PAYROLL_ACTOR).load_account(resident.account_number).balance

    def answer(letter, message, balance) = Letters::Reply.new(request: letter, ok: true, message:, balance:)

    def refuse(letter, message, reason: :refused, balance: nil)
      Letters::Reply.new(request: letter, ok: false, message:, reason:, balance:)
    end
  end
end
