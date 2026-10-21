# 申請の承認（→ その場で実行）。承認待ちの「承認する」から、Turbo Frame "approval" の中で動く:
#   new（銀行のドライランで、実行するとどうなるかの確認画面）→ create（承認して実行し、承認待ちへ）
# 申請した本人はどちらもエラー（Approvals::Desk が断る）
module Admin
  module Approvals
    class GrantsController < ApplicationController
      before_action :set_request

      def new
        @outcome = desk.approve(@request.approval_id, dry_run: true)
      rescue Banking::Error, ArgumentError => e
        @error = e.message
      end

      def create
        desk.approve(@request.approval_id)
        redirect_to admin_approvals_path, notice: "承認して、#{@request.kind_label}を実行しました", status: :see_other
      rescue Banking::Error, ArgumentError => e
        @error = e.message
        @request.reload
        render :new, status: :unprocessable_entity
      end

      private

      def set_request
        @request = ApprovalRequest.find_by!(approval_id: params[:approval_id])
      end
    end
  end
end
