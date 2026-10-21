# いまのリクエストの利用者のセッション。外からは current_customer（CustomerAuthentication のヘルパー）で使う
class CustomerCurrent < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :customer, to: :session, allow_nil: true
end
