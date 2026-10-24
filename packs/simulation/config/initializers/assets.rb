# 住民の様子の CSS（app/assets/stylesheets/simulation）を propshaft の読み込み先に足す
Rails.application.config.assets.paths << Rails.root.join("packs/simulation/app/assets/stylesheets")
