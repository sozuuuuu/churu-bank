# 口座の凍結（POST）と、凍結の解除の申請（DELETE）。
# 凍結（不正の疑いで止める）は急ぐので一人ですぐできる。解除は二人承認（TODO の Q2）で、
# ここでは申請するだけ。別の行員が承認待ち（/admin/approvals）で承認すると解除される
module Admin
  module Accounts
    class FreezesController < ApplicationController
      def create
        bank.freeze_account(number, reason: params[:reason].presence || "画面から凍結")
        redirect_to admin_account_path(number), notice: "口座を凍結しました", status: :see_other
      rescue Banking::Error => e
        redirect_to admin_account_path(number), alert: e.message, status: :see_other
      end

      def destroy
        desk.request_unfreeze(number, reason: params[:reason])
        redirect_to admin_account_path(number), notice: "凍結の解除を申請しました。別の行員が承認すると解除されます",
                                                status: :see_other
      rescue Banking::Error, ArgumentError => e
        redirect_to admin_account_path(number), alert: e.message, status: :see_other
      end

      private

      def number = params[:account_number]
    end
  end
end
