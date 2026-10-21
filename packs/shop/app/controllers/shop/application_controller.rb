# 商店の画面の土台。ログインが必要（identity の Authentication）。
# 購入者になれるのは、ログイン中の利用者にひも付いた口座（account_ownerships）だけ。行員も同じで、
# 行員だからといって他人の口座では買えない。見た目は、利用者にはねこテーマ、行員には管理画面と同じもの
module Shop
  class ApplicationController < ::ApplicationController
    include Authentication
    helper Ui::FormatHelper

    layout :shop_layout

    helper_method :current_buyer, :buyers, :cart, :store, :staff?

    private

    def store = @store ||= Shop::Store.new(actor: "shop:#{Current.user.email_address}")

    def staff? = Current.user.admin?

    # レイアウトは packs/shop/app/views/layouts/shop/*（メニューを入れて packs/ui のレイアウトで描く）
    def shop_layout = staff? ? "shop/staff" : "shop/customer"

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

    def my_account_numbers = @my_account_numbers ||= Current.user.account_numbers

    # カート: { sku => 数 }。セッションに持つ
    def cart = session[:shop_cart] ||= {}
  end
end
