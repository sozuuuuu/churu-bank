# ねこ町の住民の名簿と、町の用意（住民の利用者と口座・給料を払う口座・家賃を受け取る大家さんの口座・遊び場の口座・商店の在庫）。
# 何度流しても増えない。
# 住民は顧客台帳の利用者なので、利用者の画面（/session）から住民としてログインして、通帳や「わたしの出来事」も見られる。
# 既存の seed の利用者（オルカ・ジンジベル・ミケ）とは分けてある
module Simulation
  module Roster
    PASSWORD = "churu-dev-pass" # 開発用のテスト値（db/seeds.rb と同じ。ログインはドロップダウンなので使わない）
    EMPLOYER = "ねこ町のしごと場"
    EMPLOYER_FUNDS = 100_000
    LANDLORD = "ねこ町の大家さん"
    # 遊び場: お金を使うだけの所（在庫はいらない）。宝くじはときどき当たる（Teller::LOTTERY_ODDS）ので、宝くじ屋には元手を入れておく
    PLACES = Ractor.make_shareable([
      Memory::Place.new(key: "matatabi_bar", name: "またたびバー", price: 40),
      Memory::Place.new(key: "cat_cafe", name: "ねこカフェ", price: 60),
      Memory::Place.new(key: "onsen", name: "ひなたぼっこ温泉", price: 120),
      Memory::Place.new(key: "lottery", name: "ちゅ〜る宝くじ", price: 20)
    ])
    LOTTERY_FUNDS = 5_000
    FIRST_DEPOSIT = 200
    RESIDENTS = [
      { name: "こむぎ", email_address: "komugi@town.churu.test", temperament: :frugal },
      { name: "あずき", email_address: "azuki@town.churu.test", temperament: :impulsive },
      { name: "だいふく", email_address: "daifuku@town.churu.test", temperament: :caring },
      { name: "くるみ", email_address: "kurumi@town.churu.test", temperament: :caring },
      { name: "ころん", email_address: "koron@town.churu.test", temperament: :clumsy }
    ].freeze
    # 行員エージェント（seed の行員。いなければ行員なしで、ローンは窓口役がすぐ貸す）: [名前, 役目]
    CLERKS = [ [ "窓口のたま", :teller ], [ "係長のくろ", :chief ] ].freeze

    # 町の朝ごとに、商品がこれより少なければここまで入荷する（ごはんのちゅ〜るは多めに）
    RESTOCK = { "churu" => 30, "churu-chicken" => 30 }.freeze
    RESTOCK_OTHERS = 5

    module_function

    def setup!(residents: RESIDENTS)
      bank = Banking::Bank.new(actor: "seed")
      control = Control.current
      unless control.employer_account
        number = bank.open_account(holder_name: EMPLOYER).account_number
        bank.deposit(number, EMPLOYER_FUNDS, memo: "ねこ町のしごと場の元手")
        control.update!(employer_account: number)
      end
      unless control.landlord_account
        control.update!(landlord_account: bank.open_account(holder_name: LANDLORD).account_number)
      end
      places = (control.places || {}).dup
      PLACES.each do |place|
        next if places[place.key]

        number = bank.open_account(holder_name: place.name).account_number
        bank.deposit(number, LOTTERY_FUNDS, memo: "宝くじの元手") if place.key == Teller::LOTTERY
        places[place.key] = number
      end
      control.update!(places:)
      residents.each { add_resident(bank, **it) }
      add_clerks
      restock
      control
    end

    def add_resident(bank, name:, email_address:, temperament:)
      customer = Customer.find_or_create_by!(email_address:) do |c|
        c.name = name
        c.password = PASSWORD
      end
      if customer.account_numbers.empty?
        number = bank.open_account(holder_name: name).account_number
        customer.grant_account(number)
        bank.deposit(number, FIRST_DEPOSIT, memo: "ねこ町へようこそ")
      end
      ResidentStatus.find_or_create_by!(name:) do |status|
        status.customer = customer
        status.account_number = customer.account_numbers.first
        status.temperament = temperament.to_s
      end
    end

    # 足りない商品を入荷する（町を動かす係が朝ごとに呼ぶ。actor は町の仕入れ係）
    def restock(actor: "town-supplier")
      store = Shop::Store.new(actor:)
      return unless store.opened?

      ::ShopProduct.find_each do |product|
        level = RESTOCK.fetch(product.sku, RESTOCK_OTHERS)
        store.restock(product.sku, level - product.stock) if product.stock < level / 2 + 1
      end
    end

    def place(key) = PLACES.find { it.key == key.to_s }

    def add_clerks
      CLERKS.each do |name, role|
        staff = ::Staff.find_by(name:) or next
        ClerkStatus.find_or_create_by!(name:) { it.staff = staff; it.role = role.to_s }
      end
    end

    # 行員の Ractor に渡す設定（Clerk::Spec）。窓口は、回す先の係長の名前を持つ
    def clerk_specs(clerks = ClerkStatus.order(:id).to_a)
      chief = clerks.find(&:chief?)&.name
      clerks.map { Clerk::Spec.new(name: it.name, role: it.role.to_sym, chief:) }
    end

    FUND = "ねこ町の基金"
    FUND_ACTOR = "town-fund"

    # 住民の財布を整える: keep を超える分を基金の口座へ振り込む（町を長く動かしてお金がたまりすぎたとき）。
    # { 名前 => 振り込んだ額 } を返す。入金は振込の係（Solid Queue）がする
    def trim_wallets!(keep:)
      control = Control.current
      bank = Banking::Bank.new(actor: FUND_ACTOR)
      fund = control.places&.dig("fund") || bank.open_account(holder_name: FUND).account_number
      control.update!(places: (control.places || {}).merge("fund" => fund))
      ResidentStatus.order(:id).each_with_object({}) do |resident, moved|
        attempts = 0
        begin
          extra = bank.load_account(resident.account_number).balance - keep
          next unless extra.positive?

          bank.transfer(resident.account_number, fund, extra, memo: "ねこ町の基金へ（財布を整える）", holdable: false)
          moved[resident.name] = extra
        rescue Banking::ConcurrentModification
          # 町が動いているあいだは、住民の買いものとぶつかることがある。読み直してやり直す
          retry if (attempts += 1) < 5
        end
      end
    end

    # 住民の Ractor に渡す設定（Resident::Spec）。知り合いはほかの住民みんな、品書きは商店の商品みんな
    def specs(statuses = ResidentStatus.order(:id).to_a, seed: Random.new_seed, brain: :rules)
      menu = ::ShopProduct.order(:price).map do
        Memory::MenuItem.new(sku: it.sku, name: it.name, price: it.price, food: RESTOCK.key?(it.sku))
      end
      names = statuses.map(&:name)
      statuses.each_with_index.map do |status, index|
        Resident::Spec.new(name: status.name, temperament: status.temperament.to_sym, brain:, seed: seed + index,
                           friends: names - [ status.name ], menu:, places: PLACES)
      end
    end
  end
end
