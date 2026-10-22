# 窓口の整理券とチャット（packs/counter）。
# CSS（app/assets/stylesheets/counter）と Stimulus（app/javascript/controllers/counter）を propshaft の読み込み先に足す。
# JS はルートの config/importmap.rb で controllers/counter/* に pin している（@rails/actioncable も）
Rails.application.config.assets.paths << Rails.root.join("packs/counter/app/assets/stylesheets")
Rails.application.config.assets.paths << Rails.root.join("packs/counter/app/javascript")

# 在席（CounterPresence）は Action Cable の購読ごとの行。サーバーが止まると unsubscribed が呼ばれずに残るので、
# サーバー（bin/dev・bin/rails server）が起動したときに全部消す。コンソールやテストでは消さない
Rails.application.config.after_initialize do
  CounterPresence.delete_all if defined?(Rails::Server)
rescue ActiveRecord::ActiveRecordError
  nil # まだマイグレーションしていないときなど
end
