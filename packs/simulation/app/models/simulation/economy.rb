# 町のお金のめぐり（町を動かす係が、朝ごとに呼ぶ）。
#
# はじめは、しごと場の元手からお給料を払うだけで、住民が払ったお金は商店・大家さん・遊び場にたまる一方だった。
# 600 日でしごと場の元手が空になり、お給料が止まって、みんなローンの上限まで借りてしまった。そこで、お金が町の中をめぐるようにする:
#
#   しごと場 ──お給料──▶ 住民 ──ごはん・家賃・遊び──▶ 商店・大家さん・遊び場
#      ▲                                                  │
#      └──── 仕入れ代（商店）・お店で働く住民のお給料のもと（商店・大家さん・遊び場）────┘
#
# - 仕入れ代: 商店は入荷のたびに、値段の WHOLESALE（6 割）をしごと場に払う（ちゅ〜るを作っているのは住民、という見立て）。
#   払えるぶんしか入荷しない
# - 大家さんと遊び場は、手元に KEEP（宝くじは賞金のぶん多め）を残して、こえたぶんをしごと場に払う。
#   商店も、仕入れ代のぶん（SHOP_KEEP）を残して、こえたぶん（売り値と仕入れ値の差）を店員のお給料としてしごと場に払う
# 町から消えるのは、ちゅ〜るローンの手数料ぶんだけ（銀行の利益として町の外へ）
module Simulation
  module Economy
    ACTOR = "town-economy".freeze
    WHOLESALE = Rational(6, 10)
    KEEP = 300
    LOTTERY_KEEP = 3_000
    SHOP_KEEP = 2_000

    module_function

    # 足りない商品を、商店が払えるぶんだけ入荷し、仕入れ代をしごと場に払う。入荷した { 商品 => 数 } を返す
    def restock!(control = Control.current)
      store = Shop::Store.new(actor: ACTOR)
      return {} unless store.opened? && control.employer_account

      bank = Banking::Bank.new(actor: ACTOR)
      ::ShopProduct.order(:price).each_with_object({}) do |product, stocked|
        level = Roster::RESTOCK.fetch(product.sku, Roster::RESTOCK_OTHERS)
        next unless product.stock < level / 2 + 1

        unit = (product.price * WHOLESALE).ceil
        quantity = [ level - product.stock, bank.load_account(store.account_number).balance / unit ].min
        next unless quantity.positive?

        ActiveRecord::Base.transaction do
          bank.transfer(store.account_number, control.employer_account, unit * quantity,
                        memo: "仕入れ代（#{product.name} × #{quantity}）", holdable: false)
          store.restock(product.sku, quantity)
        end
        stocked[product.sku] = quantity
      end
    end

    # 商店・大家さん・遊び場の、手元に残すぶんをこえたお金を、しごと場に払う。払った { 口座の名義 => 額 } を返す
    def sweep!(control = Control.current)
      return {} unless control.employer_account

      bank = Banking::Bank.new(actor: ACTOR)
      payers(control).each_with_object({}) do |(number, keep), paid|
        account = bank.load_account(number)
        extra = account.balance - keep
        next unless extra.positive?

        bank.transfer(number, control.employer_account, extra, memo: "町のしごと場へ（お店で働く住民のお給料のもと）",
                                                            holdable: false)
        paid[account.holder_name] = extra
      end
    end

    # [口座番号, 残す額]。基金（財布を整えたとき預けた分）は町の外のお金なのでふくめない
    def payers(control)
      places = (control.places || {}).except("fund").map do |key, number|
        [ number, key == Teller::LOTTERY ? LOTTERY_KEEP : KEEP ]
      end
      shop = Shop::Store.new(actor: ACTOR).account_number
      [ ([ shop, SHOP_KEEP ] if shop), ([ control.landlord_account, KEEP ] if control.landlord_account), *places ].compact
    end
  end
end
