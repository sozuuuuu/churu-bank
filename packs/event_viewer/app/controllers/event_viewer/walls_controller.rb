# ふせんの壁（イベントストーミング）: 本物の記録から、出来事・命令・係・人のふせんを流れごとに並べる。
# view=patterns なら「いつもの流れ」（同じ並びの流れをまとめて数えたもの）
module EventViewer
  class WallsController < ApplicationController
    helper WallsHelper

    def show
      @wall = Wall.new(**params.permit(:correlation, :from, :to, :kind).to_h.symbolize_keys)
      @patterns = params[:view] == "patterns"
    end
  end
end
