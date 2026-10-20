# 管理画面（行員用）のベース。ログインしていて、かつ管理者でなければ入れない
module Admin
  class ApplicationController < ::ApplicationController
    include Authentication

    layout "admin"

    before_action :require_admin

    private

    # 管理者以外には、管理画面があること自体を見せない
    def require_admin
      head :not_found unless Current.user&.admin?
    end

    # 誰の操作かをイベントの metadata（actor）に残す
    def bank = @bank ||= Banking::Bank.new(actor: "admin:#{Current.user.email_address}")
  end
end
