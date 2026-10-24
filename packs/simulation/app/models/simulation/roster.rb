# ねこ町の住民の名簿と、町の用意（住民の利用者と口座・給料を払う口座・商店の在庫）。何度流しても増えない。
# 住民は顧客台帳の利用者なので、利用者の画面（/session）から住民としてログインして、通帳や「わたしの出来事」も見られる。
# 既存の seed の利用者（オルカ・ジンジベル・ミケ）とは分けてある
module Simulation
  module Roster
    PASSWORD = "churu-dev-pass" # 開発用のテスト値（db/seeds.rb と同じ。ログインはドロップダウンなので使わない）
    EMPLOYER = "ねこ町のしごと場"
    EMPLOYER_FUNDS = 100_000
    FIRST_DEPOSIT = 200
    RESIDENTS = [
      { name: "こむぎ", email_address: "komugi@town.churu.test", temperament: :frugal },
      { name: "あずき", email_address: "azuki@town.churu.test", temperament: :impulsive },
      { name: "だいふく", email_address: "daifuku@town.churu.test", temperament: :caring },
      { name: "くるみ", email_address: "kurumi@town.churu.test", temperament: :caring },
      { name: "ころん", email_address: "koron@town.churu.test", temperament: :clumsy }
    ].freeze
    # 住民がよく買う品。これより少なければ足しておく
    RESTOCK = { "churu" => 30, "churu-chicken" => 30 }.freeze

    module_function

    def setup!(residents: RESIDENTS)
      bank = Banking::Bank.new(actor: "seed")
      control = Control.current
      unless control.employer_account
        number = bank.open_account(holder_name: EMPLOYER).account_number
        bank.deposit(number, EMPLOYER_FUNDS, memo: "ねこ町のしごと場の元手")
        control.update!(employer_account: number)
      end
      residents.each { add_resident(bank, **it) }
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

    def restock
      store = Shop::Store.new(actor: "seed")
      return unless store.opened?

      RESTOCK.each do |sku, quantity|
        product = ::ShopProduct.find_by(sku:)
        store.restock(sku, quantity) if product && product.stock < 10
      end
    end

    # 住民の Ractor に渡す設定（Resident::Spec）。知り合いはほかの住民みんな、品書きは商店の商品みんな
    def specs(statuses = ResidentStatus.order(:id).to_a, seed: Random.new_seed, brain: :rules)
      menu = ::ShopProduct.order(:price).map { Memory::MenuItem.new(sku: it.sku, name: it.name, price: it.price) }
      names = statuses.map(&:name)
      statuses.each_with_index.map do |status, index|
        Resident::Spec.new(name: status.name, temperament: status.temperament.to_sym, brain:, seed: seed + index,
                           friends: names - [ status.name ], menu:)
      end
    end
  end
end
