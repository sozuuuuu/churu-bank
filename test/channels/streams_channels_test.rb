require "test_helper"

# ライブ更新の購読: 行員の画面のストリームは行員の接続から StaffStreamsChannel でだけ、
# 利用者の画面のストリームは利用者の接続から CustomerStreamsChannel でだけ。署名の鍵もチャンネルごとに別
class StaffStreamsChannelTest < ActionCable::Channel::TestCase
  test "行員の接続は、行員用に署名したストリームを購読できる" do
    stub_connection current_staff: create_staff, current_customer: nil

    subscribe signed_stream_name: StaffStreamsChannel.signed_stream_name([ "accounts" ])

    assert subscription.confirmed?
    assert_has_stream "accounts"
  end

  test "利用者の接続は、行員のストリームを購読できない（名前が正しく署名されていても）" do
    stub_connection current_staff: nil, current_customer: create_customer(name: "オルカ")

    subscribe signed_stream_name: StaffStreamsChannel.signed_stream_name([ "accounts" ])

    assert subscription.rejected?
  end

  test "利用者用に署名した名前は、行員のチャンネルでは通らない" do
    stub_connection current_staff: create_staff, current_customer: nil

    subscribe signed_stream_name: CustomerStreamsChannel.signed_stream_name([ "accounts" ])

    assert subscription.rejected?
  end
end

class CustomerStreamsChannelTest < ActionCable::Channel::TestCase
  test "利用者の接続は、利用者用に署名したストリームを購読できる" do
    stub_connection current_staff: nil, current_customer: create_customer(name: "オルカ")

    subscribe signed_stream_name: CustomerStreamsChannel.signed_stream_name([ "notices" ])

    assert subscription.confirmed?
    assert_has_stream "notices"
  end

  test "行員の接続は、利用者のチャンネルを購読できない" do
    stub_connection current_staff: create_staff, current_customer: nil

    subscribe signed_stream_name: CustomerStreamsChannel.signed_stream_name([ "notices" ])

    assert subscription.rejected?
  end

  test "行員用に署名した名前（行員の画面のストリーム）は、利用者のチャンネルでは通らない" do
    stub_connection current_staff: nil, current_customer: create_customer(name: "オルカ")

    subscribe signed_stream_name: StaffStreamsChannel.signed_stream_name([ "transfers" ])

    assert subscription.rejected?
  end
end

class PlainTurboStreamsChannelTest < ActionCable::Channel::TestCase
  tests Turbo::StreamsChannel

  test "素の Turbo::StreamsChannel はだれも購読できない" do
    stub_connection current_staff: create_staff, current_customer: create_customer(name: "オルカ")

    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ "accounts" ])

    assert subscription.rejected?
  end
end
