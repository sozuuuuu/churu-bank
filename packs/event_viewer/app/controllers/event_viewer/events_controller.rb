# イベントの一覧と生中継（index）、1件の中身とつながりの図（show）
module EventViewer
  class EventsController < ApplicationController
    def index
      @search = Search.new(**params.permit(:kind, :account, :date, :before).to_h.symbolize_keys)
      @accounts = ::Account.order(:number)
    end

    def show
      @flow = Flow.around(params[:id])
      @event = @flow.seed
      @streams = Rails.configuration.event_store.streams_of(@event.event_id).map(&:name)
    rescue Flow::NotFound
      head :not_found
    end
  end
end
