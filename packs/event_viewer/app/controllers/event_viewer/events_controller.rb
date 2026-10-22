# イベントの一覧と生中継（index）、1件の中身とつながりの図（show）
module EventViewer
  class EventsController < ApplicationController
    def index
      @search = EventLens::Search.new(**params.permit(:kind, :account, :date, :before).to_h.symbolize_keys)
      @accounts = ::Account.order(:number)
    end

    def show
      @flow = EventLens::Flow.around(params[:id])
      @event = @flow.seed
      @streams = Rails.configuration.event_store.streams_of(@event.event_id).map(&:name)
    rescue EventLens::Flow::NotFound
      head :not_found
    end
  end
end
