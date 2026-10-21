# 画面の共通部品の CSS（packs/ui/app/assets/stylesheets）を propshaft の読み込み先に足す。
# ルートの stylesheet_link_tag :app には入らないので、使うレイアウト（layouts/cat）だけが読み込む
Rails.application.config.assets.paths << Rails.root.join("packs/ui/app/assets/stylesheets")
