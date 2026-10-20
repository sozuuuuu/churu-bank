# 利用者画面の CSS（packs/customer/app/assets/stylesheets）を propshaft の読み込み先に足す。
# ルートの stylesheet_link_tag :app には入らないので、利用者画面のレイアウトだけが読み込む
Rails.application.config.assets.paths << Rails.root.join("packs/customer/app/assets/stylesheets")
