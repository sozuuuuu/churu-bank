module Notices
  # ねこの吹き出しから閉じる（既読にもなる）。重要なお知らせは、閉じるまで吹き出しに出し続ける
  class DismissalsController < ApplicationController
    def create
      NoticeReceipt.dismiss!(find_notice(params[:notice_id]), current_customer)
      redirect_back_or_to notices_path
    end
  end
end
