# 窓口の整理券と窓口チャットの唯一の入口（書き込み）。利用者の画面・行員の画面・チャンネルから呼ぶ。
# 書いたあとで、Action Cable のチャンネルに知らせる（Counter::Broadcasts。何がどこへ流れるかは README の図）
#
#   利用者 take（札を取る）/ give_back（札を返す）/ speak（発言）
#   行員   call_next（次の方）/ finish（終わる）/ speak（発言。呼んだ本人だけ）
module Counter
  class Desk
    MAX_MESSAGE_LENGTH = 500
    WITHDRAWAL_GUIDE = "出金のご依頼は、口座のページの「出金の依頼」からお願いします。出していただければ、窓口でそのまま処理します。".freeze

    class Error < StandardError; end
    class Busy < Error; end         # その行員は、まだほかの人と話している（先に「終わる」）
    class NotAllowed < Error; end   # その人はこのチャットで発言できない
    class InvalidState < Error; end # もう終わった札など

    class << self
      # 番号札を取る。もう持っていればその札を返す（2枚は持てない）
      def take(customer)
        attempts = 0
        begin
          existing = CounterTicket.active.find_by(customer:)
          return existing if existing

          date = Time.zone.today
          ticket = CounterTicket.create!(service_date: date, number: CounterTicket.where(service_date: date).maximum(:number).to_i + 1,
                                         customer:, taken_at: Time.current)
        rescue ActiveRecord::RecordNotUnique
          # 同時に取った人と番号がぶつかった（か、同じ人が2回押した）。もう一度
          retry if (attempts += 1) < 3
          raise
        end
        Broadcasts.queue_changed
        ticket
      end

      # 札を返す（待っているあいだも、呼ばれたあとも）。持っていなければ nil
      def give_back(customer)
        ticket = CounterTicket.active.find_by(customer:)
        return unless ticket

        was_called = ticket.called?
        ticket.update!(status: "returned", closed_at: Time.current, closed_by: customer.actor)
        Broadcasts.closed(ticket) if was_called
        Broadcasts.queue_changed
        ticket
      end

      # 次の方を呼ぶ。待っている人がいなければ nil。ほかの行員と同時に押しても、1枚の札を呼ぶのは1人だけ
      def call_next(staff)
        raise Busy, "#{staff.name} さんは、まだほかのお客さまと話しています" if CounterTicket.called.exists?(staff_id: staff.id)

        3.times do
          candidate = CounterTicket.waiting.first
          return unless candidate

          now = Time.current
          called = CounterTicket.where(id: candidate.id, status: "waiting")
                                .update_all(status: "called", called_at: now, staff_id: staff.id, staff_name: staff.name, updated_at: now)
          next if called.zero? # ほかの行員が先に呼んだ。次の札へ

          ticket = candidate.reload
          Broadcasts.called(ticket)
          Broadcasts.queue_changed
          return ticket
        end
        nil
      end

      # チャットを終えて、札を「終わり」にする。呼んだ行員でなくてもよい（席を外した人の代わりに閉じられるように）
      def finish(ticket_id, staff)
        ticket = CounterTicket.find(ticket_id)
        raise InvalidState, "#{ticket.number} 番はもう#{ticket.status_label}です" unless ticket.called?

        ticket.update!(status: "finished", closed_at: Time.current, closed_by: staff.actor)
        Broadcasts.closed(ticket)
        Broadcasts.queue_changed
        ticket
      end

      # チャットで発言する。role は "customer" / "staff"、person はその人（Customer / Staff）。
      # 利用者は自分の札、行員は自分が呼んだ札だけ。空なら何もしない（nil）
      def speak(ticket_id, role:, person:, body:, kind: "text")
        ticket = CounterTicket.find(ticket_id)
        raise NotAllowed, "このチャットでは発言できません" unless can_speak?(ticket, role, person)
        raise NotAllowed, "出金の案内は行員だけが出せます" if kind == "withdrawal_guide" && role != "staff"

        body = kind == "withdrawal_guide" ? WITHDRAWAL_GUIDE : body.to_s.strip
        return if body.empty?

        message = ticket.messages.create!(author_role: role, author_id: person.id, author_name: person.name, kind:,
                                          body: body.truncate(MAX_MESSAGE_LENGTH), created_at: Time.current)
        Broadcasts.message(message)
        message
      end

      def can_speak?(ticket, role, person)
        return false unless ticket.called? && person

        case role
        when "customer" then ticket.customer_id == person.id
        when "staff" then ticket.speakable_by_staff?(person)
        else false
        end
      end
    end
  end
end
