# 利用者のお知らせの画面（/notices）の土台。ログインが必要。見られるのは、いま掲載中で自分が対象のものだけ
module Notices
  class ApplicationController < ::ApplicationController
    include Authentication
    helper Ui::FormatHelper
    helper Notices::InboxHelper

    layout "notices/customer"

    helper_method :inbox

    private

    # ヘルパー（notices_inbox）と同じものを使う
    def inbox = @notices_inbox ||= Inbox.new(Current.user)

    # 期間外・対象外のお知らせは「ない」ものとして 404 にする
    def find_notice(id) = Notice.live.for_user(Current.user).find(id)
  end
end
