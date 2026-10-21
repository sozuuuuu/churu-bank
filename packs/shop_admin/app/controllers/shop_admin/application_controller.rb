# 商品・在庫の管理のベース。行員としてログインしていなければ、行員のログイン画面へ（packs/staff_identity）
module ShopAdmin
  class ApplicationController < ::ApplicationController
    include StaffAuthentication
    helper Ui::FormatHelper

    layout "shop_admin"

    private

    # 誰の操作かをイベントの metadata（actor）に残す（staff:<id>）
    def store = @store ||= Shop::Store.new(actor: current_staff.actor)
  end
end
