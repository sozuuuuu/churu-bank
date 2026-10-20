# 商店の画面の土台。ルートの ApplicationController は別パッケージ（ルート）にあって依存できないので、
# ActionController::Base から直接作る。レイアウトと churu などのヘルパーは名前で借りている
# （定数の参照ではないので packwerk には見えない依存。README の「packwerk の気づき」を参照）
module Shop
  class ApplicationController < ActionController::Base
    allow_browser versions: :modern
    layout "application"

    helper_method :current_buyer, :buyers, :cart, :store

    private

    def store = @store ||= Shop::Store.new(actor: "web")

    # 購入者。いまは画面で選んだ口座をセッションに持つだけ。
    # 認証（packs/identity）ができたら、ログイン中の利用者にひも付いた口座に差し替える
    def current_buyer
      return @current_buyer if defined?(@current_buyer)

      @current_buyer = session[:shop_buyer] && buyers.find_by(number: session[:shop_buyer])
    end

    # 購入者になれる口座（商店自身の口座は除く）
    def buyers = Account.where(status: "active").where.not(number: store.account_number).order(:number)

    # カート: { sku => 数 }。セッションに持つ
    def cart = session[:shop_cart] ||= {}
  end
end
