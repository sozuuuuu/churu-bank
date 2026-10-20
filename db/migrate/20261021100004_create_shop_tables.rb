# ちゅ〜る商店（packs/shop）の読み取りモデル。正はイベントストアなので、どれも作り直せる
class CreateShopTables < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_products do |t|
      t.string :sku, null: false, index: { unique: true }
      t.string :name, null: false
      t.string :emoji
      t.integer :price, null: false
      t.integer :stock, null: false, default: 0
      t.timestamps
    end

    create_table :shop_orders do |t|
      t.string :order_id, null: false, index: { unique: true }
      t.string :buyer_account, null: false, index: true
      t.integer :total, null: false
      t.string :status, null: false
      t.string :payment_transfer_id, index: true
      t.string :refund_transfer_id, index: true
      t.string :failure_reason
      t.datetime :placed_at, null: false
      t.string :actor
      t.timestamps
    end

    create_table :shop_order_lines do |t|
      t.string :order_id, null: false, index: true
      t.string :sku, null: false
      t.string :name, null: false
      t.integer :unit_price, null: false
      t.integer :quantity, null: false
      t.timestamps
    end
  end
end
