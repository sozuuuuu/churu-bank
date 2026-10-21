# 商店の画面（買い物）の土台。利用者としてログインしていなければ、利用者のログイン画面へ（packs/customer_identity）。
# 購入者になれるのは、ログイン中の利用者にひも付いた口座（account_ownerships）だけ。
# 商品と在庫の管理（行員）は別のパック packs/shop_admin（/shop/admin）。行員が買い物をするなら利用者のアカウントで
module Shop
  class ApplicationController < ::ApplicationController
    include CustomerAuthentication
    helper Ui::FormatHelper

    layout "shop/customer"

    helper_method :current_buyer, :buyers, :cart, :store

    private

    # 誰の操作かをイベントの metadata（actor）に残す（customer:<id>）
    def store = @store ||= Shop::Store.new(actor: current_customer.actor)

    # 購入者（口座）。選んだ口座をセッションに持つが、使うたびに自分の口座の中から探し直す。
    # 選んでいなければ自分の最初の口座
    def current_buyer
      return @current_buyer if defined?(@current_buyer)

      @current_buyer = buyers.find_by(number: session[:shop_buyer]) || buyers.first
    end

    # 購入者になれる口座: 自分の口座のうち、使えるもの（商店自身の口座は除く）
    def buyers
      Account.where(number: my_account_numbers, status: "active").where.not(number: store.account_number).order(:number)
    end

    def my_account_numbers = @my_account_numbers ||= current_customer.account_numbers

    # カート: { sku => 数 }。セッションに持つ
    def cart = session[:shop_cart] ||= {}
  end
end
