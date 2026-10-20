# 口座の凍結（POST）と解除（DELETE）
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
        bank.unfreeze_account(number)
        redirect_to admin_account_path(number), notice: "凍結を解除しました", status: :see_other
      rescue Banking::Error => e
        redirect_to admin_account_path(number), alert: e.message, status: :see_other
      end

      private

      def number = params[:account_number]
    end
  end
end
