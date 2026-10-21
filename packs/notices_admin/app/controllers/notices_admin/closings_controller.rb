module NoticesAdmin
  # 掲載を終える（ends_at を今に）。消さないので、だれが読んだかは残る
  class ClosingsController < ApplicationController
    def create
      board.close(params[:notice_id])
      redirect_to notices_admin_notices_path, notice: "掲載を終えました"
    end
  end
end
