# 画面の係（メインの Ractor）: 住民の Report・見張り役の Restarted・時計の Tick・手紙を表に書き、行員の画面「住民の様子」へ
# Turbo Stream で配る。町を動かす係は Puma とは別のプロセスだが、Solid Cable（表 solid_cable_messages）を通すので届く
#
#   住民1匹のカード・町の時計・借金の関係図 … replace
#   手紙の流れ … 1通ずつ頭に prepend（画面には新しい 40 通、表には KEEP 通まで）
module Simulation
  class Board
    STREAM = "simulation:town".freeze
    STATUS_TARGET = "simulation_status".freeze
    LETTERS_TARGET = "simulation_letters".freeze
    DEBTS_TARGET = "simulation_debts".freeze
    TELLER = "窓口役".freeze
    SUPERVISOR = "見張り役".freeze
    # 返事が ok なら、借金の関係図を書き直す手紙
    MONEY_LETTERS = [ Letters::WantLoan, Letters::WantLend, Letters::WantRepay ].freeze

    def report(letter)
      status = ResidentStatus.find_by(name: letter.name) or return
      attributes = { state: letter.state, mood: letter.mood, money: letter.money, last_action: letter.last_action,
                     letters_received: letter.received, letters_sent: letter.sent }
      status.last_action_at = Time.current if status.last_action != letter.last_action
      status.update!(attributes)
      resident(status)
    end

    def restarted(letter)
      status = ResidentStatus.find_by(name: letter.name) or return
      status.update!(restarts: letter.count, last_error: letter.reason)
      resident(status)
      record(SUPERVISOR, letter.name, "restart", "#{letter.count} 回目の起こし直し（#{letter.reason}）")
    end

    def clock(tick)
      Control.current.update!(day: tick.day, time: tick.time.to_s)
      status
    end

    # 手紙1通を書き残して、手紙の流れの頭に足す。時計の合図は書かない
    def letter(sender, recipient, letter)
      kind, text = LetterText.describe(letter)
      record(sender, recipient, kind, text) if kind
    end

    # 町を動かしはじめるとき、起こし直した回数を 0 に戻す
    def reset
      ResidentStatus.update_all(restarts: 0, last_error: nil)
      ResidentStatus.find_each { resident(it) }
      debts
    end

    def resident(status)
      broadcast(:replace, target: ActionView::RecordIdentifier.dom_id(status),
                          partial: "simulation/residents/resident", locals: { resident: status })
    end

    def status
      broadcast(:replace, target: STATUS_TARGET, partial: "simulation/residents/status", locals: { control: Control.current })
    end

    def debts
      broadcast(:replace, target: DEBTS_TARGET, partial: "simulation/residents/debts", locals: DebtWeb.locals)
    end

    private

    def record(sender, recipient, kind, text)
      row = Letter.create!(sender:, recipient:, kind:, text:, day: Control.current.day)
      Letter.prune! if (row.id % 50).zero?
      broadcast(:prepend, target: LETTERS_TARGET, partial: "simulation/residents/letter", locals: { letter: row })
    end

    def broadcast(action, target:, partial:, locals:)
      html = ResidentsController.render(partial:, locals:)
      Turbo::StreamsChannel.broadcast_action_to(STREAM, action:, target:, html:)
    end
  end
end
