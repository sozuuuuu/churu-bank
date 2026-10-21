# お知らせの CSS（app/assets/stylesheets/notices）と Stimulus（app/javascript/controllers/notices）を propshaft の読み込み先に足す。
# CSS は notices_inbox と行員のレイアウトが読み込む。JS はルートの config/importmap.rb で controllers/notices/* に pin している
Rails.application.config.assets.paths << Rails.root.join("packs/notices/app/assets/stylesheets")
Rails.application.config.assets.paths << Rails.root.join("packs/notices/app/javascript")
