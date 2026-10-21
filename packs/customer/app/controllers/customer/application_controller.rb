# 利用者画面のベース。ログインが必要で、見られる口座は自分のものだけ
module Customer
  class ApplicationController < ::ApplicationController
    include Authentication
    helper Ui::FormatHelper
    helper Notices::InboxHelper # 銀行からのお知らせ（レイアウトの notices_inbox）

    layout "customer"

    private

    def my_accounts = Account.where(number: Current.user.account_numbers)

    # 他人の口座は「ない」ものとして 404 にする（あるかどうかも教えない）
    def find_my_account(number) = my_accounts.find_by!(number:)

    def bank = @bank ||= Banking::Bank.new(actor: "customer:#{Current.user.email_address}")
  end
end
