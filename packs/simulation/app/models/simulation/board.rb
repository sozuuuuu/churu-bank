# 画面の係（メインの Ractor）: 住民の Report・見張り役の Restarted・時計の Tick を表に書き、行員の画面「住民の様子」へ
# Turbo Stream（replace）で配る。町を動かす係は Puma とは別のプロセスだが、Solid Cable（表 solid_cable_messages）を通すので届く
module Simulation
  class Board
    STREAM = "simulation:town".freeze
    STATUS_TARGET = "simulation_status".freeze

    def report(letter)
      status = ResidentStatus.find_by(name: letter.name) or return
      attributes = { state: letter.state, mood: letter.mood, money: letter.money, last_action: letter.last_action }
      status.last_action_at = Time.current if status.last_action != letter.last_action
      status.update!(attributes)
      resident(status)
    end

    def restarted(letter)
      status = ResidentStatus.find_by(name: letter.name) or return
      status.update!(restarts: letter.count, last_error: letter.reason)
      resident(status)
    end

    def clock(tick)
      Control.current.update!(day: tick.day, time: tick.time.to_s)
      status
    end

    # 町を動かしはじめるとき、起こし直した回数を 0 に戻す
    def reset
      ResidentStatus.update_all(restarts: 0, last_error: nil)
      ResidentStatus.find_each { resident(it) }
    end

    def resident(status)
      broadcast(target: ActionView::RecordIdentifier.dom_id(status),
                partial: "simulation/residents/resident", locals: { resident: status })
    end

    def status
      broadcast(target: STATUS_TARGET, partial: "simulation/residents/status", locals: { control: Control.current })
    end

    private

    def broadcast(target:, partial:, locals:)
      html = ResidentsController.render(partial:, locals:)
      Turbo::StreamsChannel.broadcast_replace_to(STREAM, target:, html:)
    end
  end
end
