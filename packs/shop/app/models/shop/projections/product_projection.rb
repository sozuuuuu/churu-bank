# イベント → 読み取りモデル（shop_products）。publish と同じトランザクションで同期的に呼ばれる
module Shop
  module Projections
    class ProductProjection
      def call(event)
        data = event.data
        case event
        when Events::ProductListed
          ShopProduct.create!(sku: data.fetch(:sku), name: data.fetch(:name), emoji: data[:emoji],
                              price: data.fetch(:price), stock: 0)
        when Events::ProductPriceChanged
          find(event).update!(price: data.fetch(:price))
        when Events::StockAdded
          find(event).increment!(:stock, data.fetch(:quantity))
        when Events::StockAllocated
          find(event).decrement!(:stock, data.fetch(:quantity))
        end
      end

      private

      def find(event) = ShopProduct.find_by!(sku: event.data.fetch(:sku))
    end
  end
end
