module Notices
  module Admin
    class NoticesController < ApplicationController
      before_action :set_notice, only: %i[edit update]
      before_action :set_users, only: %i[new create edit update]

      def index
        @notices = Notice.order(starts_at: :desc, id: :desc).includes(:target_users)
        @read_counts = NoticeReceipt.where.not(read_at: nil).group(:notice_id).count
      end

      def new
        @notice = Notice.new(kind: "info", audience: "everyone", starts_at: Time.current.change(sec: 0))
      end

      def create
        @notice = board.post(**notice_params)
        if @notice.persisted?
          redirect_to notices_admin_notices_path, notice: "お知らせを出しました"
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        board.revise(@notice, **notice_params)
        if @notice.errors.empty?
          redirect_to notices_admin_notices_path, notice: "お知らせを直しました"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def set_notice
        @notice = Notice.find(params[:id])
      end

      # 対象に選べるのは利用者（行員は除く）
      def set_users
        @users = User.where(admin: false).order(:id)
      end

      def notice_params
        params.expect(notice: [ :kind, :title, :body, :important, :starts_at, :ends_at, :audience, target_user_ids: [] ])
              .to_h.symbolize_keys
      end
    end
  end
end
