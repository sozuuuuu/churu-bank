module Notices
  class NoticesController < ApplicationController
    def index
      @notices = inbox.notices
    end

    # 開いたら既読
    def show
      @notice = find_notice(params[:id])
      NoticeReceipt.read!(@notice, Current.user)
    end
  end
end
