# 利用者画面にお知らせを差し込む部品。画面のパックのベースコントローラで helper Notices::InboxHelper し、
# レイアウトで render template: "layouts/cat" より前に <%= notices_inbox %> を1回呼ぶと、次のものが入る:
#   - content_for :head     … お知らせの CSS（notices/notices.css）
#   - content_for :nav      … メニューの「お知らせ」と未読のバッジ
#   - content_for :page_top … ねこの吹き出し（packs/ui の layouts/application が main の頭に出す）
#   - ライブ更新の購読（全員向けの "notices" と、その人だけの [user, :notices]）
module Notices
  module InboxHelper
    # bubble: false なら吹き出しは出さない（お知らせの一覧のページなど）
    def notices_inbox(bubble: true)
      return unless Current.user

      inbox = @notices_inbox ||= Notices::Inbox.new(Current.user)
      content_for :head, stylesheet_link_tag("notices/notices", "data-turbo-track": "dynamic")
      content_for :nav, render("notices/inbox/nav_link", inbox:)
      content_for :page_top, render("notices/inbox/board", inbox:, bubble:)
      nil
    end
  end
end
