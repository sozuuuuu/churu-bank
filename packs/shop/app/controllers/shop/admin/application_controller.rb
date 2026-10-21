# 商品・在庫の管理のベース。行員（User#admin）だけ。そうでなければ 404（管理画面と同じく、あることも見せない）
module Shop
  module Admin
    class ApplicationController < Shop::ApplicationController
      before_action :require_staff

      private

      def require_staff
        head :not_found unless staff?
      end
    end
  end
end
