# 窓口の列とチャット（行員）の CSS（app/assets/stylesheets/counter_admin）を propshaft の読み込み先に足す
Rails.application.config.assets.paths << Rails.root.join("packs/counter_admin/app/assets/stylesheets")
