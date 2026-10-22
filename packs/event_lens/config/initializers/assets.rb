# イベントを読み解く部品の CSS（app/assets/stylesheets/event_lens）と Stimulus（app/javascript/controllers/event_lens）を
# propshaft の読み込み先に足す。JS はルートの config/importmap.rb で controllers/event_lens/* に pin している
Rails.application.config.assets.paths << Rails.root.join("packs/event_lens/app/assets/stylesheets")
Rails.application.config.assets.paths << Rails.root.join("packs/event_lens/app/javascript")
