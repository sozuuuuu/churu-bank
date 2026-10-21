# 管理画面の CSS（packs/admin/app/assets/stylesheets）を propshaft の読み込み先に足す。
# layouts/admin が data-turbo-track="dynamic" で読み込むので、利用者画面には効かない
Rails.application.config.assets.paths << Rails.root.join("packs/admin/app/assets/stylesheets")
