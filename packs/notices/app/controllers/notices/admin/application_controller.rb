# 行員のお知らせの画面（/admin/notices）の土台。行員（User#admin）だけ。そうでなければ 404（管理画面と同じく、あることも見せない）
module Notices
  module Admin
    class ApplicationController < ::ApplicationController
      include Authentication
      helper Ui::FormatHelper

      layout "notices/staff"

      before_action :require_staff

      private

      def require_staff
        head :not_found unless Current.user&.admin?
      end

      def board = @board ||= Notices::Board.new(actor: "admin:#{Current.user.email_address}")
    end
  end
end
