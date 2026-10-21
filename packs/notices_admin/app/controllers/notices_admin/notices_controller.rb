module NoticesAdmin
  class NoticesController < ApplicationController
    before_action :set_notice, only: %i[edit update]
    before_action :set_customers, only: %i[new create edit update]

    def index
      @notices = Notice.order(starts_at: :desc, id: :desc).includes(:target_customers)
      @read_counts = Notice.read_counts
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

    # 対象に選べるのは利用者（顧客台帳）
    def set_customers
      @customers = Customer.order(:id)
    end

    def notice_params
      params.expect(notice: [ :kind, :title, :body, :important, :starts_at, :ends_at, :audience, target_customer_ids: [] ])
            .to_h.symbolize_keys
    end
  end
end
