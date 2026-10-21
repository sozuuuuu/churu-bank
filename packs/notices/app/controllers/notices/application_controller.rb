# 利用者のお知らせの画面（/notices）の土台。利用者としてのログインが必要（packs/customer_identity）。見られるのは、いま掲載中で自分が対象のものだけ
module Notices
  class ApplicationController < ::ApplicationController
    include CustomerAuthentication
    helper Ui::FormatHelper
    helper Ui::ThemeHelper # アイコン・ねこ・セリフ窓（layouts/cat が使う）
    helper Notices::InboxHelper

    layout "notices/customer"

    helper_method :inbox

    private

    # ヘルパー（notices_inbox）と同じものを使う
    def inbox = @notices_inbox ||= Inbox.new(current_customer)

    # 期間外・対象外のお知らせは「ない」ものとして 404 にする
    def find_notice(id) = Notice.live.for_customer(current_customer).find(id)
  end
end
