# 窓口チャット（札ごとの部屋）。双方向: ブラウザから perform("speak") / perform("typing") を送り、
# サーバーは同じ部屋の全員に broadcast_to する。
#
# 購読のときに params の role（"customer" / "staff"）で、どちらとして入るかを決め、接続の持ち主で確かめる:
#   - 利用者: 利用者としてつないでいて、その札の持ち主で、札が「対応中」のとき
#   - 行員:   行員としてつないでいて、札が「対応中」のとき（だれでも見られる。発言できるのは呼んだ行員だけ）
# 同じブラウザで行員と利用者の両方にログインしていると、接続は両方を持つので、role で分ける。
# 購読しているあいだは在席（CounterPresence）。入ったり出たりしたら、部屋のみんなに presence を送る
module Counter
  class ChatChannel < ActionCable::Channel::Base
    def subscribed
      @role = params[:role].to_s
      @ticket = CounterTicket.find_by(id: params[:ticket_id])
      return reject unless @ticket&.called? && person && allowed?

      stream_for @ticket
      @presence = CounterPresence.create!(room: @ticket.room, role: @role, person_id: person.id, name: person.name,
                                          created_at: Time.current)
      Broadcasts.presence(@ticket, role: @role)
      # 相手がもういるかを、自分にだけすぐ送る
      transmit Broadcasts.presence_payload(@ticket, other_role)
    end

    def unsubscribed
      return unless @presence

      @presence.destroy
      Broadcasts.presence(@ticket, role: @role)
    end

    # ブラウザから: 発言する（data: { body: }）。行員は kind: "withdrawal_guide" で出金依頼の画面へ案内できる
    def speak(data)
      Desk.speak(@ticket.id, role: @role, person:, body: data["body"], kind: data["kind"].presence || "text")
    rescue Desk::Error, ActiveRecord::RecordInvalid => e
      transmit({ type: "error", message: e.message })
    end

    # ブラウザから: 入力中（保存しない。相手の画面に「入力中…」を少しのあいだ出す）
    def typing(_data = nil)
      Broadcasts.typing(@ticket, role: @role) if Desk.can_speak?(@ticket.reload, @role, person)
    end

    private

    def person
      case @role
      when "customer" then current_customer
      when "staff" then current_staff
      end
    end

    def allowed?
      @role == "staff" || @ticket.customer_id == current_customer.id
    end

    def other_role = @role == "staff" ? "customer" : "staff"
  end
end
