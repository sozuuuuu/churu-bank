module Notices
  class NoticesController < ApplicationController
    def index
      @notices = inbox.notices
    end

    # 開いたら既読。ただしホバーでの先読み（Turbo の prefetch）では既読にしない（リンク側でも止めている）。
    # 先読みの応答はクリックで使われることもあるので、キャッシュさせない
    def show
      @notice = find_notice(params[:id])
      if request.headers["X-Sec-Purpose"] == "prefetch"
        response.headers["Cache-Control"] = "no-store"
      else
        NoticeReceipt.read!(@notice, Current.user)
      end
    end
  end
end
