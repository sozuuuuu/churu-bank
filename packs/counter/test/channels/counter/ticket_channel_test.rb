require "test_helper"

# 自分の番号札のチャンネル: 購読できるのは、利用者としてつないだその札の持ち主だけ
class Counter::TicketChannelTest < ActionCable::Channel::TestCase
  setup do
    @mike = create_customer(name: "ミケ")
    @ginger = create_customer(name: "ジンジベル")
    Counter::Desk.take(@ginger)
    @ticket = Counter::Desk.take(@mike)
  end

  test "自分の札は購読でき、つないだ時点の順番がすぐ届く" do
    stub_connection current_staff: nil, current_customer: @mike

    subscribe ticket_id: @ticket.id

    assert subscription.confirmed?
    assert_has_stream_for @ticket
    assert_equal({ "type" => "position", "number" => 2, "ahead" => 1, "staff_at_counter" => false }, transmissions.last)
  end

  test "他人の札は購読できない" do
    stub_connection current_staff: nil, current_customer: @ginger

    subscribe ticket_id: @ticket.id

    assert subscription.rejected?
  end

  test "行員の接続では利用者の札は購読できない" do
    stub_connection current_staff: create_staff, current_customer: nil

    subscribe ticket_id: @ticket.id

    assert subscription.rejected?
  end

  test "返した札は購読できない" do
    Counter::Desk.give_back(@mike)
    stub_connection current_staff: nil, current_customer: @mike

    subscribe ticket_id: @ticket.id

    assert subscription.rejected?
  end

  test "前の人が呼ばれると、自分の札に「前に 0 人」が届く" do
    stub_connection current_staff: nil, current_customer: @mike
    subscribe ticket_id: @ticket.id

    assert_broadcast_on(Counter::TicketChannel.broadcasting_for(@ticket),
                        { type: "position", number: 2, ahead: 0, staff_at_counter: false }) do
      Counter::Desk.call_next(create_staff(name: "たま"))
    end
  end
end
