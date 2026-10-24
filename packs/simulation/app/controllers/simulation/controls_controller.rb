# 町の起動・停止・速さ。表 simulation_controls に書くだけで、町を動かす係（bin/rails churu:simulate）が1秒以内に読んで従う。
# Ractor は Puma の中では動かさない（README の「ねこ町の住民の暮らし」）
module Simulation
  class ControlsController < ApplicationController
    def update
      control = Control.current
      if control.update(params.expect(control: %i[running seconds_per_day]))
        redirect_to simulation_residents_path, notice: notice_for(control)
      else
        redirect_to simulation_residents_path, alert: control.errors.full_messages.to_sentence
      end
    end

    private

    def notice_for(control)
      return "速さを「#{Control::SPEEDS.fetch(control.seconds_per_day)}」にしました。" unless control.saved_change_to_running?
      return "町を止めるよう頼みました。" unless control.running

      control.keeper_alive? ? "町を動かすよう頼みました。" : "町を動かす係が止まっています。bin/rails churu:simulate を動かしてください。"
    end
  end
end
