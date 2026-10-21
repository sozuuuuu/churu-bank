# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# パックの Stimulus（読み込み先は各パックの config/initializers/assets.rb で足している）。識別子は notices--inbox など
pin_all_from "packs/notices/app/javascript/controllers/notices", under: "controllers/notices"
