require "test_helper"

# 整理券の順番・呼び出し・チャットの開始と終了（Counter::Desk）と、そのときチャンネルへ流れるもの
class Counter::DeskTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @tama = create_staff(name: "たま")
    @kuro = create_staff(name: "くろ")
    @ginger = create_customer(name: "ジンジベル")
    @mike = create_customer(name: "ミケ")
    @orca = create_customer(name: "オルカ")
  end

  test "札の番号は日ごとに 1 から順に。前に何人かは取った順" do
    a = Counter::Desk.take(@ginger)
    b = Counter::Desk.take(@mike)
    c = Counter::Desk.take(@orca)

    assert_equal [ 1, 2, 3 ], [ a, b, c ].map(&:number)
    assert_equal [ 0, 1, 2 ], [ a, b, c ].map(&:ahead)
  end

  test "札は1人1枚。もう持っていれば同じ札が返る" do
    first = Counter::Desk.take(@ginger)

    assert_equal first, Counter::Desk.take(@ginger)
    assert_equal 1, CounterTicket.count
  end

  test "札を取ると、待っている札それぞれに「前に何人」が流れる" do
    ginger = Counter::Desk.take(@ginger)

    assert_broadcast_on(Counter::TicketChannel.broadcasting_for(ginger),
                        { type: "position", number: 1, ahead: 0, staff_at_counter: false }) do
      Counter::Desk.take(@mike)
    end
  end

  test "次の方で前から順に呼ぶ。呼ばれた人には called、呼ばれなかった人は前に 1 人へ" do
    ginger = Counter::Desk.take(@ginger)
    Counter::Desk.take(@mike)
    orca = Counter::Desk.take(@orca)

    assert_broadcast_on(Counter::TicketChannel.broadcasting_for(ginger), { type: "called", number: 1, staff_name: "たま" }) do
      assert_broadcast_on(Counter::TicketChannel.broadcasting_for(orca), { type: "position", number: 3, ahead: 1, staff_at_counter: false }) do
        assert_equal ginger, Counter::Desk.call_next(@tama)
      end
    end
    ginger.reload
    assert ginger.called?
    assert_equal @tama.id, ginger.staff_id
    assert_equal "たま", ginger.staff_name
  end

  test "2人の行員が呼ぶと、それぞれ別の人を呼ぶ" do
    Counter::Desk.take(@ginger)
    Counter::Desk.take(@mike)

    assert_equal "ジンジベル", Counter::Desk.call_next(@tama).customer.name
    assert_equal "ミケ", Counter::Desk.call_next(@kuro).customer.name
    assert_nil Counter::Desk.call_next(create_staff(name: "しろ")) # もうだれも待っていない
  end

  test "話している途中の行員は、次の方を呼べない（先に終わる）" do
    Counter::Desk.take(@ginger)
    Counter::Desk.take(@mike)
    Counter::Desk.call_next(@tama)

    assert_raises(Counter::Desk::Busy) { Counter::Desk.call_next(@tama) }
  end

  test "札を返すと列から抜け、後ろの人が進む" do
    Counter::Desk.take(@ginger)
    mike = Counter::Desk.take(@mike)

    returned = Counter::Desk.give_back(@ginger)

    assert_equal "returned", returned.status
    assert_equal @ginger.actor, returned.closed_by
    assert_equal 0, mike.ahead
    assert_nil Counter::Desk.give_back(@ginger) # もう持っていない
  end

  test "発言は札の利用者と、呼んだ行員だけ。ほかの行員・他人は NotAllowed" do
    ticket = start_chat(@ginger, @tama)

    broadcasts = capture_broadcasts(Counter::ChatChannel.broadcasting_for(ticket)) do
      Counter::Desk.speak(ticket.id, role: "customer", person: @ginger, body: " 出金したいです ")
    end
    assert_equal({ "type" => "message", "role" => "customer", "name" => "ジンジベル", "kind" => "text", "body" => "出金したいです" },
                 broadcasts.sole.slice("type", "role", "name", "kind", "body"))
    Counter::Desk.speak(ticket.id, role: "staff", person: @tama, body: "はい、どうぞ")

    assert_equal [ "出金したいです", "はい、どうぞ" ], ticket.messages.pluck(:body)
    assert_raises(Counter::Desk::NotAllowed) { Counter::Desk.speak(ticket.id, role: "staff", person: @kuro, body: "横から") }
    assert_raises(Counter::Desk::NotAllowed) { Counter::Desk.speak(ticket.id, role: "customer", person: @mike, body: "他人") }
    assert_raises(Counter::Desk::NotAllowed) { Counter::Desk.speak(ticket.id, role: "customer", person: @ginger, body: "", kind: "withdrawal_guide") }
    assert_nil Counter::Desk.speak(ticket.id, role: "customer", person: @ginger, body: "   ") # 空は何もしない
  end

  test "出金依頼の画面への案内は、決まった文で残る" do
    ticket = start_chat(@ginger, @tama)

    message = Counter::Desk.speak(ticket.id, role: "staff", person: @tama, body: nil, kind: "withdrawal_guide")

    assert_equal "withdrawal_guide", message.kind
    assert_match "出金の依頼", message.body
  end

  test "終わると札は終わりになり、チャットと札に closed が流れ、もう発言できない。行員は次の方を呼べる" do
    ticket = start_chat(@ginger, @tama)
    Counter::Desk.take(@mike)

    closed = { type: "closed", number: ticket.number, status: "finished", by: "staff" }
    assert_broadcast_on(Counter::ChatChannel.broadcasting_for(ticket), closed) do
      assert_broadcast_on(Counter::TicketChannel.broadcasting_for(ticket), closed) do
        Counter::Desk.finish(ticket.id, @tama)
      end
    end

    assert_equal "finished", ticket.reload.status
    assert_equal @tama.actor, ticket.closed_by
    assert_raises(Counter::Desk::NotAllowed) { Counter::Desk.speak(ticket.id, role: "customer", person: @ginger, body: "まだ") }
    assert_raises(Counter::Desk::InvalidState) { Counter::Desk.finish(ticket.id, @tama) }
    assert_equal "ミケ", Counter::Desk.call_next(@tama).customer.name
  end

  test "列が変わると、行員の列のストリームに changed が流れる" do
    assert_broadcast_on(Counter::QueueChannel::STREAM, { type: "changed" }) do
      Counter::Desk.take(@ginger)
    end
  end

  test "記録は消さずに残る（札・呼んだ行員・発言）" do
    ticket = start_chat(@ginger, @tama)
    Counter::Desk.speak(ticket.id, role: "staff", person: @tama, body: "こんにちは")
    Counter::Desk.finish(ticket.id, @tama)

    record = CounterTicket.closed.first
    assert_equal [ 1, "ジンジベル", "たま", "finished" ], [ record.number, record.customer.name, record.staff_name, record.status ]
    assert record.taken_at && record.called_at && record.closed_at
    assert_equal [ "こんにちは" ], record.messages.pluck(:body)
  end

  private

  # 利用者が札を取り、行員が呼んだところまで（チャットが始まった状態）
  def start_chat(customer, staff)
    Counter::Desk.take(customer)
    Counter::Desk.call_next(staff)
  end
end
