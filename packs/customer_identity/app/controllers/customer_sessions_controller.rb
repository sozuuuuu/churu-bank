# 利用者のログイン（new / create）とログアウト（destroy）。/session。見た目はねこテーマ
class CustomerSessionsController < ApplicationController
  include CustomerAuthentication
  helper Ui::FormatHelper # packs/ui のレイアウト（layouts/cat）を使うしるし
  helper Ui::ThemeHelper # アイコン・ねこ・セリフ窓（layouts/cat が使う）

  allow_unauthenticated_customer_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_customer_session_path, alert: "しばらくしてからもう一度お試しください" }

  layout "cat"

  def new
  end

  def create
    if customer = Customer.authenticate_by(params.permit(:email_address, :password))
      start_new_customer_session_for customer
      redirect_to after_customer_authentication_url
    else
      redirect_to new_customer_session_path, alert: "メールアドレスかパスワードがちがいます"
    end
  end

  def destroy
    terminate_customer_session
    redirect_to new_customer_session_path, status: :see_other
  end
end
