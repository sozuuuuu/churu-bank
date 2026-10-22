# 行員が窓口の列（待っている札・対応中の札）の変化を受け取るチャンネル。行員としてつないだ接続だけ。
# 購読しているあいだは「窓口に行員がいる」（在席）として数え、待っている利用者の画面に出す
module Counter
  class QueueChannel < ActionCable::Channel::Base
    STREAM = "counter:queue"

    def subscribed
      return reject unless current_staff

      stream_from STREAM
      @presence = CounterPresence.create!(room: CounterPresence::LOBBY, role: "staff", person_id: current_staff.id,
                                          name: current_staff.name, created_at: Time.current)
      Broadcasts.queue_changed
    end

    def unsubscribed
      return unless @presence

      @presence.destroy
      Broadcasts.queue_changed
    end
  end
end
