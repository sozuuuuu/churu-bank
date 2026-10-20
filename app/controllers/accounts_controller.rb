class AccountsController < ApplicationController
  before_action :set_account, only: %i[show balance]

  def index
    @accounts = Account.order(:number)
  end

  def show
    @entries = @account.ledger_entries.reverse_order.limit(100)
    @date = parse_date(params[:date]) || Date.current
  end

  def new; end

  def create
    outcome = bank.open_account(holder_name: params[:holder_name].to_s.strip)
    redirect_to account_path(outcome.account_number), notice: "口座を開設しました"
  rescue Banking::Error, ArgumentError => e
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
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
    @account = Account.find_by!(number: params[:number])
  end
end
