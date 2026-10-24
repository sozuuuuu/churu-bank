# 窓口役（メインの Ractor）: 住民の手紙（Letters::REQUESTS）を確かめて、これまでどおり銀行（Banking::Bank）と
# 商店（Shop::Store）の公開の入口で書く。ActiveRecord もイベントストアも、ここ（メイン）でだけ使う。
#
# 確かめること: 町の住民か・相手も住民か（自分あては不可）・金額の範囲・給料日／家賃の日か（同じ日に2回は払わない）・
# 売り切れか・残高が足りるか（銀行のドライランで。足りなければ :insufficient で断る）・もう借りられるか（:loan_limit）。
# 断ったら返事（Letters::Reply）でわけを伝える。返事にはいつも、その住民の借金の帳面（debts）を付ける。
#
#   家賃      … 住民 → ねこ町の大家さん の振込
#   遊び場    … 住民 → 遊び場（またたびバー・ねこカフェ・温泉・宝くじ）の振込。宝くじはときどき当たって、宝くじ屋から賞金
#   ちゅ〜るローン … 銀行の Bank#lend / Bank#repay_loan
#   住民どうしの貸し借り … 振込 + 借用書（表 simulation_debts。町の記録で、銀行は知らない）
#
# 書いた出来事の metadata には resident（住民の名前）を付ける（印）。だれがは actor（住民の利用者 customer:<id>。給料は town-payroll）。
# 印は RES の with_metadata で付けるので、銀行・商店の側は住民のことを知らないまま。
# 振込の後半（入金）や商店の引き当ては、いつもどおり Solid Queue のジョブが続ける（そちらには印は付かない。つながりは correlation_id でたどれる）
module Simulation
  class Teller
    PAYROLL_ACTOR = "town-payroll".freeze
    LOTTERY_ACTOR = "town-lottery".freeze
    RENT = 45
    MAX_TRANSFER = 100
    MAX_LEND = 100
    MAX_QUANTITY = 3
    LOTTERY = "lottery".freeze
    LOTTERY_ODDS = 0.08
    LOTTERY_PRIZE = 200

    attr_accessor :today # いちばん新しい時計の合図（Letters::Tick）

    # residents: { 名前 => ResidentStatus }、places: { 遊び場の名前 => 口座番号 }
    def initialize(residents:, employer_account:, landlord_account: nil, places: {},
                   event_store: Rails.configuration.event_store, random: Random.new)
      @residents = residents
      @employer_account = employer_account
      @landlord_account = landlord_account
      @places = places
      @event_store = event_store
      @random = random
    end

    # 手紙1通に、返事（Letters::Reply）を1通返す
    def handle(letter)
      resident = @residents[letter.from]
      return refuse(letter, "町の住民ではありません") unless resident

      @resident = resident
      case letter
      when Letters::AskBalance then answer(letter, "残高は #{balance(resident)} ちゅ〜るです", balance(resident))
      when Letters::AskSalary then pay_salary(letter, resident)
      when Letters::PayRent then pay_rent(letter, resident)
      when Letters::WantTransfer then transfer(letter, resident)
      when Letters::WantPurchase then purchase(letter, resident)
      when Letters::WantFun then have_fun(letter, resident)
      when Letters::WantLoan then borrow(letter, resident)
      when Letters::WantLend then lend(letter, resident)
      when Letters::WantRepay then repay(letter, resident)
      else refuse(letter, "その手紙はあつかっていません")
      end
    rescue Banking::InsufficientFunds => e
      refuse(letter, e.message, reason: :insufficient, balance: resident && balance(resident))
    rescue Banking::Error, Shop::Error, ArgumentError => e
      refuse(letter, e.message, balance: resident && balance(resident))
    ensure
      @resident = nil
    end

    # 行員エージェントが承認したローンを貸す（actor はその行員。住民の印も付ける）。[返事, 貸付ID] を返す
    def lend_for(letter, actor:)
      resident = @residents[letter.from]
      return [ refuse(letter, "町の住民ではありません"), nil ] unless resident

      @resident = resident
      outcome = mark(resident) { bank(actor).lend(resident.account_number, letter.amount, memo: "ねこ町の暮らしのため") }
      total = letter.amount + Banking::Bank.loan_fee(letter.amount)
      [ answer(letter, "ちゅ〜るローンで #{letter.amount} ちゅ〜る借りました（返すのは #{total} ちゅ〜る）", outcome.balance_after),
        outcome.loan_id ]
    rescue Banking::InvalidState => e
      [ refuse(letter, e.message, reason: :loan_limit, balance: balance(resident)), nil ]
    rescue Banking::Error, ArgumentError => e
      [ refuse(letter, e.message, balance: balance(resident)), nil ]
    ensure
      @resident = nil
    end

    # 行員エージェントが断ったローンの申込への返事
    def reject_loan(letter, reason)
      resident = @residents[letter.from]
      @resident = resident
      refuse(letter, "ちゅ〜るローンは審査で断られました（#{reason}）", reason: :loan_rejected,
                     balance: resident && balance(resident))
    ensure
      @resident = nil
    end

    # 住民の借金の帳面: { 貸した住民の名前 か Letters::BANK => まだ返していない額 }
    def debts_of(resident)
      debts = Debt.owed_by(resident.name)
      bank = ::Loan.owed_by(resident.account_number)
      debts[Letters::BANK] = bank if bank.positive?
      Ractor.make_shareable(debts)
    end

    private

    def pay_salary(letter, resident)
      unless today&.payday && today.day == letter.day
        return refuse(letter, "きょうは給料日ではありません", reason: :not_payday, balance: balance(resident))
      end
      if resident.paid_day == letter.day
        return refuse(letter, "#{letter.day} 日目の給料はもう払いました", reason: :not_payday, balance: balance(resident))
      end

      salary = Temperament.fetch(resident.temperament).salary
      before = balance(resident)
      mark(resident) do
        bank(PAYROLL_ACTOR).transfer(@employer_account, resident.account_number, salary,
                                     memo: "ねこ町のお給料（#{letter.day} 日目）", holdable: false)
      end
      resident.update!(paid_day: letter.day)
      # 入金はこのあと振込の係（Solid Queue）がするので、見込みとして足しておく
      answer(letter, "お給料 #{salary} ちゅ〜るを振り込みました", before + salary)
    end

    def pay_rent(letter, resident)
      unless @landlord_account && today&.rent_day && today.day == letter.day
        return refuse(letter, "きょうは家賃の日ではありません", reason: :not_payday, balance: balance(resident))
      end
      if resident.rent_paid_day == letter.day
        return refuse(letter, "#{letter.day} 日目の家賃はもう払いました", reason: :not_payday, balance: balance(resident))
      end

      outcome = pay(resident, @landlord_account, RENT, memo: "家賃（#{letter.day} 日目）")
      resident.update!(rent_paid_day: letter.day)
      answer(letter, "大家さんに家賃 #{RENT} ちゅ〜るを払いました", outcome.balance_after)
    end

    def transfer(letter, resident)
      to = @residents[letter.to]
      return refuse(letter, "#{letter.to}さんは町の住民ではありません") unless to
      return refuse(letter, "自分には振り込めません") if to == resident
      unless letter.amount.is_a?(Integer) && letter.amount.between?(1, MAX_TRANSFER)
        return refuse(letter, "振込は 1〜#{MAX_TRANSFER} ちゅ〜るまでです", balance: balance(resident))
      end

      outcome = pay(resident, to.account_number, letter.amount, memo: letter.memo)
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

    # 遊び場: 値段ぶん遊び場の口座へ振り込む。宝くじはときどき当たる（賞金は宝くじ屋の口座から）
    def have_fun(letter, resident)
      place = Roster.place(letter.place)
      account = @places[letter.place.to_s]
      return refuse(letter, "その遊び場はありません", balance: balance(resident)) unless place && account

      outcome = pay(resident, account, place.price, memo: place.name)
      return answer(letter, "#{place.name}で #{place.price} ちゅ〜る使いました", outcome.balance_after) unless place.key == LOTTERY
      return answer(letter, "#{place.name}は、はずれでした", outcome.balance_after) unless @random.rand < LOTTERY_ODDS

      mark(resident) do
        bank(LOTTERY_ACTOR).transfer(account, resident.account_number, LOTTERY_PRIZE, memo: "宝くじの当たり", holdable: false)
      end
      answer(letter, "#{place.name}が当たって、#{LOTTERY_PRIZE} ちゅ〜るもらいました！", outcome.balance_after + LOTTERY_PRIZE)
    end

    def borrow(letter, resident)
      outcome = mark(resident) do
        bank(resident.customer.actor).lend(resident.account_number, letter.amount, memo: "ねこ町の暮らしのため")
      end
      total = letter.amount + Banking::Bank.loan_fee(letter.amount)
      answer(letter, "ちゅ〜るローンで #{letter.amount} ちゅ〜る借りました（返すのは #{total} ちゅ〜る）", outcome.balance_after)
    rescue Banking::InvalidState => e
      refuse(letter, e.message, reason: :loan_limit, balance: balance(resident))
    end

    # 住民どうしで貸す: 振込と、借用書（Debt）を1つのトランザクションで
    def lend(letter, resident)
      to = @residents[letter.to]
      return refuse(letter, "#{letter.to}さんは町の住民ではありません") unless to
      return refuse(letter, "自分には貸せません") if to == resident
      unless letter.amount.is_a?(Integer) && letter.amount.between?(1, MAX_LEND)
        return refuse(letter, "貸すのは 1〜#{MAX_LEND} ちゅ〜るまでです", balance: balance(resident))
      end

      outcome = ActiveRecord::Base.transaction do
        Debt.create!(lender: resident.name, borrower: to.name, amount: letter.amount, day: today&.day)
        pay(resident, to.account_number, letter.amount, memo: "#{to.name}さんに貸す（借用書あり）")
      end
      answer(letter, "#{to.name}さんに #{letter.amount} ちゅ〜る貸しました", outcome.balance_after)
    end

    def repay(letter, resident)
      return repay_bank(letter, resident) if letter.to == Letters::BANK

      lender = @residents[letter.to]
      return refuse(letter, "#{letter.to}さんは町の住民ではありません") unless lender

      owed = Debt.owed_by(resident.name)[lender.name].to_i
      return refuse(letter, "#{lender.name}さんには借りていません", balance: balance(resident)) if owed.zero?

      amount = [ letter.amount.to_i, owed ].min
      return refuse(letter, "返す額は 1 ちゅ〜る以上です", balance: balance(resident)) unless amount.positive?

      outcome = ActiveRecord::Base.transaction do
        Debt.settle!(borrower: resident.name, lender: lender.name, amount:)
        pay(resident, lender.account_number, amount, memo: "#{lender.name}さんへ借りたお金を返す")
      end
      answer(letter, "#{lender.name}さんに #{amount} ちゅ〜る返しました（のこり #{owed - amount} ちゅ〜る）",
             outcome.balance_after)
    end

    # 銀行のちゅ〜るローンを返す（古い貸付から）
    def repay_bank(letter, resident)
      loan = ::Loan.open.where(account_number: resident.account_number).order(:granted_at, :id).first
      return refuse(letter, "銀行には借りていません", balance: balance(resident)) unless loan

      amount = [ letter.amount.to_i, loan.outstanding ].min
      return refuse(letter, "返す額は 1 ちゅ〜る以上です", balance: balance(resident)) unless amount.positive?

      bank = bank(resident.customer.actor)
      bank.repay_loan(loan.loan_id, amount, from: resident.account_number, dry_run: true)
      outcome = mark(resident) { bank.repay_loan(loan.loan_id, amount, from: resident.account_number) }
      LoanCase.where(loan_id: loan.loan_id).update_all(last_repaid_day: today.day) if today # 延滞の数えなおし
      answer(letter, "ちゅ〜るローンを #{amount} ちゅ〜る返しました", outcome.balance_after)
    end

    # 住民の口座から振り込む（ドライランで残高を確かめてから。足りなければ InsufficientFunds）
    def pay(resident, to_account, amount, memo:)
      bank = bank(resident.customer.actor)
      bank.transfer(resident.account_number, to_account, amount, memo:, holdable: false, dry_run: true)
      mark(resident) { bank.transfer(resident.account_number, to_account, amount, memo:, holdable: false) }
    end

    # この中で書いた出来事に、住民の印を付ける
    def mark(resident, &) = @event_store.with_metadata(resident: resident.name, &)

    def bank(actor) = Banking::Bank.new(actor:, event_store: @event_store)

    def balance(resident) = bank(PAYROLL_ACTOR).load_account(resident.account_number).balance

    def answer(letter, message, balance)
      Letters::Reply.new(request: letter, ok: true, message:, balance:, debts: current_debts)
    end

    def refuse(letter, message, reason: :refused, balance: nil)
      Letters::Reply.new(request: letter, ok: false, message:, reason:, balance:, debts: current_debts)
    end

    def current_debts = @resident && debts_of(@resident)
  end
end
