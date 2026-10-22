# ストリーム名・口座番号・actor を、画面に出す日本語にする。
#   Account$0000001 → 口座 0000001（オルカ）、Transfer$c49f… → 振込 #c49f、staff:1 → 窓口のたま（行員）
# 口座と商品の名前は公開の読み取りモデル（Account・ShopProduct）から、1画面につき1回だけまとめて引く。
# 人の名前は、見る画面が people で渡す（行員の画面は行員と利用者の全員、利用者の画面は本人だけ）。
# 渡されなかった人は「銀行の行員」「ほかのお客さま」とだけ出す（このパックはログインのパックに依存しない）
module EventLens
  class Names
    # people: { "staff" => { "1" => "窓口のたま" }, "customer" => { "1" => "オルカ" } }
    def initialize(people: {})
      @people = people
    end
    # 人ではない actor（ジョブ・初期データなど）
    MACHINE_ACTORS = {
      "seed" => "はじめのデータ", "transfer-settlement" => "振込の処理（自動）", "transfer-scheduler" => "予約振込の実行（自動）",
      "shop-payment" => "商店の支払いの処理（自動）", "interest" => "利息の計算（自動）", "mcp" => "MCP（AI のお手伝い）",
      "web" => "画面"
    }.freeze
    PEOPLE = { "staff" => "行員", "customer" => "利用者" }.freeze
    UNNAMED_PEOPLE = { "staff" => "銀行の行員", "customer" => "ほかのお客さま" }.freeze

    # ID が UUID のストリーム。日本語の頭と、UUID の頭4文字で見せる
    STREAM_KINDS = {
      "Transfer" => "振込", "Order" => "注文", "WithdrawalRequest" => "出金依頼", "Approval" => "承認の申請",
      "ShopTransfer" => "商店の振込の目印"
    }.freeze

    def account(number)
      return number.to_s if number.blank?

      holder = holders[number.to_s]
      holder ? "#{number}（#{holder}）" : number.to_s
    end

    def holder(number) = holders[number.to_s]

    def product(sku) = products[sku.to_s]

    # short: true なら口座の名義を省く（図の小さい字の欄）
    def stream(name, short: false)
      kind, id = name.to_s.split("$", 2)
      return name.to_s if id.nil?

      case kind
      when "Account" then "口座 #{short ? id : account(id)}"
      when "Product" then "商品 #{products[id] || id}"
      when "Shop" then "ちゅ〜る商店"
      when *STREAM_KINDS.keys then "#{STREAM_KINDS.fetch(kind)} #{short(id)}"
      else name.to_s
      end
    end

    # レーン図の見出しの2行: [上の段（種類と番号）, 下の段（名前）]
    def stream_parts(name)
      kind, id = name.to_s.split("$", 2)
      case kind
      when "Account" then [ "口座 #{id}", holder(id) || id ]
      when "Product" then [ "商品", products[id] || id ]
      when "Shop" then [ "商店", "ちゅ〜る商店" ]
      when *STREAM_KINDS.keys then [ STREAM_KINDS.fetch(kind), short(id) ]
      else [ "", name.to_s ]
      end
    end

    def actor(actor)
      return "（記録なし）" if actor.blank?

      kind, id = actor.to_s.split(":", 2)
      if (name = @people.dig(kind, id))
        "#{name}（#{PEOPLE.fetch(kind)}）"
      elsif UNNAMED_PEOPLE.key?(kind) && id.to_s.match?(/\A\d+\z/)
        UNNAMED_PEOPLE.fetch(kind)
      else
        MACHINE_ACTORS[actor.to_s] || actor.to_s
      end
    end

    def short(id) = "##{id.to_s.first(4)}"

    private

    def holders = @holders ||= ::Account.pluck(:number, :holder_name).to_h

    def products = @products ||= ::ShopProduct.pluck(:sku, :name).to_h
  end
end
