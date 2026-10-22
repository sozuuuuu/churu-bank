# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# パックの Stimulus（読み込み先は各パックの config/initializers/assets.rb で足している）。識別子は notices--inbox など
pin_all_from "packs/notices/app/javascript/controllers/notices", under: "controllers/notices"
pin_all_from "packs/event_lens/app/javascript/controllers/event_lens", under: "controllers/event_lens"
pin_all_from "packs/counter/app/javascript/controllers/counter", under: "controllers/counter"
# Action Cable のブラウザ側（actioncable の gem に入っている ESM 版）。窓口の整理券とチャット（packs/counter）が自分で購読に使う
pin "@rails/actioncable", to: "actioncable.esm.js"
