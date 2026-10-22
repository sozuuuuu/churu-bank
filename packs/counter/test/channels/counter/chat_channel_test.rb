require "test_helper"

# 窓口チャットのチャンネル: 入れるのは札の利用者（role: customer）と行員（role: staff）。発言・入力中・在席・終わり
class Counter::ChatChannelTest < ActionCable::Channel::TestCase
  setup do
    @tama = create_staff(name: "たま")
    @mike = create_customer(name: "ミケ")
    Counter::Desk.take(@mike)
    @ticket = Counter::Desk.call_next(@tama)
  end

  test "札の利用者は入れる。在席が部屋に流れ、相手（行員）がいるかが自分にだけ届く" do
    stub_connection current_staff: nil, current_customer: @mike

    assert_broadcast_on(Counter::ChatChannel.broadcasting_for(@ticket),
                        { type: "presence", role: "customer", present: true, names: [ "ミケ" ] }) do
      subscribe ticket_id: @ticket.id, role: "customer"
    end

    assert subscription.confirmed?
    assert_has_stream_for @ticket
    assert_equal({ "type" => "presence", "role" => "staff", "present" => false, "names" => [] }, transmissions.last)
  end

  test "抜けると在席でなくなる" do
    stub_connection current_staff: @tama, current_customer: nil
    subscribe ticket_id: @ticket.id, role: "staff"
    assert @ticket.present?("staff")

    assert_broadcast_on(Counter::ChatChannel.broadcasting_for(@ticket),
                        { type: "presence", role: "staff", present: false, names: [] }) do
      unsubscribe
    end
    assert_not @ticket.present?("staff")
  end

  test "他人の札のチャットには入れない" do
    stub_connection current_staff: nil, current_customer: create_customer(name: "ジンジベル")

    subscribe ticket_id: @ticket.id, role: "customer"

    assert subscription.rejected?
  end

  test "利用者の接続で role: staff と名乗っても入れない（行員として確かめる）" do
    stub_connection current_staff: nil, current_customer: @mike

    subscribe ticket_id: @ticket.id, role: "staff"

    assert subscription.rejected?
  end

  test "行員の接続で role: customer と名乗っても入れない" do
    stub_connection current_staff: @tama, current_customer: nil

    subscribe ticket_id: @ticket.id, role: "customer"

    assert subscription.rejected?
  end

  test "まだ呼ばれていない札・終わった札のチャットには入れない" do
    waiting = Counter::Desk.take(create_customer(name: "オルカ"))
    Counter::Desk.finish(@ticket.id, @tama)
    stub_connection current_staff: @tama, current_customer: nil

    subscribe ticket_id: waiting.id, role: "staff"
    assert subscription.rejected?

    subscribe ticket_id: @ticket.id, role: "staff"
    assert subscription.rejected?
  end

  test "利用者が speak すると発言が残り、部屋に流れる" do
    stub_connection current_staff: nil, current_customer: @mike
    subscribe ticket_id: @ticket.id, role: "customer"

    broadcasts = capture_broadcasts(Counter::ChatChannel.broadcasting_for(@ticket)) do
      perform :speak, body: "出金をおねがいします"
    end

    message = @ticket.messages.sole
    assert_equal [ "customer", @mike.id, "ミケ", "出金をおねがいします" ], [ message.author_role, message.author_id, message.author_name, message.body ]
    assert_equal message.to_broadcast.as_json, broadcasts.sole
  end

  test "呼んだ行員は発言でき、出金依頼の画面へ案内できる" do
    stub_connection current_staff: @tama, current_customer: nil
    subscribe ticket_id: @ticket.id, role: "staff"

    perform :speak, body: "いらっしゃいませ"
    perform :speak, kind: "withdrawal_guide"

    assert_equal %w[text withdrawal_guide], @ticket.messages.pluck(:kind)
  end

  test "呼んでいない行員は見られるが、発言はできない（error が自分にだけ届く）" do
    stub_connection current_staff: create_staff(name: "くろ"), current_customer: nil
    subscribe ticket_id: @ticket.id, role: "staff"
    assert subscription.confirmed?

    perform :speak, body: "横から失礼"

    assert_empty @ticket.messages
    assert_equal "error", transmissions.last["type"]
  end

  test "入力中は保存せずに部屋に流れる" do
    stub_connection current_staff: nil, current_customer: @mike
    subscribe ticket_id: @ticket.id, role: "customer"

    assert_broadcast_on(Counter::ChatChannel.broadcasting_for(@ticket), { type: "typing", role: "customer" }) do
      perform :typing
    end
    assert_empty @ticket.messages
  end

  test "行員が終わると、部屋に closed が流れる" do
    stub_connection current_staff: nil, current_customer: @mike
    subscribe ticket_id: @ticket.id, role: "customer"

    assert_broadcast_on(Counter::ChatChannel.broadcasting_for(@ticket),
                        { type: "closed", number: @ticket.number, status: "finished", by: "staff" }) do
      Counter::Desk.finish(@ticket.id, @tama)
    end
  end
end
