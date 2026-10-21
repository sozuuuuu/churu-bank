# 行員のログイン・ログアウト（/admin/session）。利用者の /session とは別
resource :session, only: %i[new create destroy], path: "admin/session", controller: "staff_sessions", as: :staff_session
