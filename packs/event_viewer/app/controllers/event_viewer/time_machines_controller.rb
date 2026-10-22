# タイムマシン: 口座を選んで、出来事を1件ずつ足していく（起算日の順 / 記帳日の順）
module EventViewer
  class TimeMachinesController < ApplicationController
    def show
      @accounts = ::Account.order(:number)
      number = params[:account].presence || @accounts.first&.number
      @account = @accounts.find { it.number == number }
      @machine = EventLens::TimeMachine.new(@account.number, basis: params[:basis]) if @account
    end
  end
end
