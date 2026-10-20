# 商品と在庫の集約（ストリーム "Product$<sku>"）。在庫数はこの集約の中だけで計算する。
#
# 同じ商品を2つの注文が同時に引き当てようとしても、ストリームの expected_version で
# 後から来た方が失敗する（ジョブがやり直して、在庫が足りなければ返金になる）ので、在庫がマイナスにならない。
module Shop
  class Product
    include AggregateRoot

    attr_reader :sku, :name, :emoji, :price, :stock

    def initialize(sku)
      @sku = sku
      @status = :unlisted
      @stock = 0
      @allocated_orders = Set.new
    end

    def self.stream_name(sku) = "Product$#{sku}"

    def listed? = @status == :listed

    def list(name:, price:, emoji: nil)
      raise AlreadyListed, "商品 #{sku} はすでにあります" if listed?
      raise ArgumentError, "商品コードは英数字と - _ で入れてください" unless sku.to_s.match?(/\A[a-z0-9_-]+\z/i)
      raise ArgumentError, "商品名を入れてください" if name.blank?
      ensure_positive!(price, "値段")

      apply Events::ProductListed.new(data: { sku:, name:, emoji: emoji.presence, price: })
    end

    def change_price(price)
      ensure_listed!
      ensure_positive!(price, "値段")
      apply Events::ProductPriceChanged.new(data: { sku:, price: })
    end

    def restock(quantity)
      ensure_listed!
      ensure_positive!(quantity, "数")
      apply Events::StockAdded.new(data: { sku:, quantity: })
    end

    # 支払い済みの注文に在庫を引き当てる。同じ注文で2回呼ばれても1回分だけ
    def allocate(order_id:, quantity:)
      ensure_listed!
      return if @allocated_orders.include?(order_id)
      if quantity > stock
        raise OutOfStock, "#{name} の在庫が足りません（在庫 #{stock} / 注文 #{quantity}）"
      end

      apply Events::StockAllocated.new(data: { sku:, order_id:, quantity: })
    end

    on Events::ProductListed do |event|
      @name = event.data.fetch(:name)
      @emoji = event.data[:emoji]
      @price = event.data.fetch(:price)
      @status = :listed
    end

    on Events::ProductPriceChanged do |event|
      @price = event.data.fetch(:price)
    end

    on Events::StockAdded do |event|
      @stock += event.data.fetch(:quantity)
    end

    on Events::StockAllocated do |event|
      @stock -= event.data.fetch(:quantity)
      @allocated_orders << event.data.fetch(:order_id)
    end

    private

    def ensure_listed!
      raise NotFound, "商品 #{sku} はありません" unless listed?
    end

    def ensure_positive!(value, label)
      raise ArgumentError, "#{label}は1以上の整数で入れてください" unless value.is_a?(Integer) && value.positive?
    end
  end
end
