# いまのリクエストの行員のセッション。外からは current_staff（StaffAuthentication のヘルパー）で使う
class StaffCurrent < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :staff, to: :session, allow_nil: true
end
