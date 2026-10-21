# 利用者のログイン・ログアウト（/session）。行員の /admin/session とは別
resource :session, only: %i[new create destroy], controller: "customer_sessions", as: :customer_session
