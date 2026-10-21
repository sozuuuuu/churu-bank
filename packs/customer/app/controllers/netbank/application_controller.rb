# 利用者画面のベース。利用者としてログインしていなければ、利用者のログイン画面（/session/new）へ。
# 行員としてログインしていても入れない（Cookie もセッションも別。packs/customer_identity）。見られる口座は自分のものだけ
module Netbank
  class ApplicationController < ::ApplicationController
    include CustomerAuthentication
    helper Ui::FormatHelper
    helper Notices::InboxHelper # 銀行からのお知らせ（レイアウトの notices_inbox）

    layout "customer"

    private

    def my_accounts = Account.where(number: current_customer.account_numbers)

    # 他人の口座は「ない」ものとして 404 にする（あるかどうかも教えない）
    def find_my_account(number) = my_accounts.find_by!(number:)

    # 誰の操作かをイベントの metadata（actor）に残す（customer:<id>）
    def bank = @bank ||= Banking::Bank.new(actor: current_customer.actor)
  end
end
