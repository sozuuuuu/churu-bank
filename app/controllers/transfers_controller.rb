class TransfersController < ApplicationController
  def index
    @transfers = Transfer.includes(:source, :destination).order(requested_at: :desc).limit(100)
  end
end
