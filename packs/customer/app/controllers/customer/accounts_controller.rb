module Customer
  class AccountsController < ApplicationController
    before_action :set_account, only: %i[show balance]

    def index
      @accounts = my_accounts.order(:number)
    end

    def show
      @entries = @account.ledger_entries.reverse_order.limit(100)
      @transfers = Transfer.where(transfer_id: @entries.filter_map(&:transfer_id)).index_by(&:transfer_id)
      @holders = Account.where(number: @entries.filter_map(&:counterparty)).pluck(:number, :holder_name).to_h
      @my_numbers = Current.user.account_numbers
      @date = parse_date(params[:date]) || Date.current
    end

    # 時点指定の残高。起算日基準と記帳日基準を並べて出す
    def balance
      @date = parse_date(params[:date]) || Date.current
      # Frame の遷移で URL が /balance?date= になるので、リロードや morph 更新で直接開かれたら口座ページへ
      return redirect_to account_path(@account, date: @date) unless turbo_frame_request?

      @as_of = Banking::Statement.new(@account.number, date: @date, basis: :as_of)
      @as_at = Banking::Statement.new(@account.number, date: @date, basis: :as_at)
    end

    private

    def parse_date(value)
      Date.iso8601(value) if value.present?
    rescue Date::Error
      nil
    end

    def set_account
      @account = find_my_account(params[:number])
    end
  end
end
