require "test_helper"

# 行員の列のチャンネル: 行員としてつないだ接続だけ。購読しているあいだは「窓口に行員がいる」
class Counter::QueueChannelTest < ActionCable::Channel::TestCase
  test "行員は購読でき、在席になる。待っている利用者に staff_at_counter が届く。抜けると在席でなくなる" do
    ticket = Counter::Desk.take(create_customer(name: "ミケ"))
    stub_connection current_staff: create_staff(name: "たま"), current_customer: nil

    assert_broadcast_on(Counter::TicketChannel.broadcasting_for(ticket),
                        { type: "position", number: 1, ahead: 0, staff_at_counter: true }) do
      subscribe
    end
    assert subscription.confirmed?
    assert_has_stream Counter::QueueChannel::STREAM

    assert_broadcast_on(Counter::TicketChannel.broadcasting_for(ticket),
                        { type: "position", number: 1, ahead: 0, staff_at_counter: false }) do
      unsubscribe
    end
  end

  test "利用者の接続では購読できない" do
    stub_connection current_staff: nil, current_customer: create_customer(name: "ミケ")

    subscribe

    assert subscription.rejected?
    assert_no_streams
  end
end
