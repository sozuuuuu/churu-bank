# 住民の様子: 住民ごとの今の状態・最後にしたこと・見張り役が起こし直した回数。町を動かす係（別のプロセス）が
# Turbo Stream（Board::STREAM）で1匹ずつ書き換える。起動・停止・速さは ControlsController へ
module Simulation
  class ResidentsController < ApplicationController
    def index
      @control = Control.current
      @residents = ResidentStatus.order(:id)
      @letters = Letter.recent
      @debts = DebtWeb.locals
    end
  end
end
