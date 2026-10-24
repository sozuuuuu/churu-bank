require "test_helper"

# ねこの実況の文: 行員の画面は名前も金額も全部、利用者の画面は「あなた」「ほかのお客さま」で、行員の名前を出さない
class EventLens::CommentaryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @tama = create_staff(name: "窓口のたま")
    bank = Banking::Bank.new(actor: @tama.actor)
    @orca = bank.open_account(holder_name: "オルカ").account_number
    @mike = bank.open_account(holder_name: "ミケ").account_number
    bank.deposit(@orca, 1000)
    perform_enqueued_jobs { Banking::Bank.new(actor: "customer:1").transfer(@orca, @mike, 50) }
  end

  def event_store = Rails.configuration.event_store
  def last(type) = event_store.read.of_type(type).last
  def staff_names = EventLens::Names.new(people: { "staff" => { @tama.id.to_s => "窓口のたま" } })
  def for_staff = EventLens::Commentary.new(names: staff_names)
  def for_customer(*accounts) = EventLens::Commentary.new(names: EventLens::Names.new, own_accounts: accounts)

  test "すべてのイベントに、実況の文と表情がある（足し忘れを見つける）" do
    missing = EventLens::Catalog::ENTRIES.keys.reject { EventLens::Commentary::LINES.key?(it) }
    assert_empty missing, "実況の文がないイベント: #{missing.join(', ')}"
    EventLens::Commentary::LINES.each do |type, (face, _)|
      assert Ui::ThemeHelper::CAT_FACES.key?(face), "#{type} の表情 #{face}"
    end
  end

  test "行員の画面: だれからだれへ、いくら" do
    line = for_staff.line(last(Banking::Events::TransferRequested))
    assert_equal "いまオルカさんからミケさんへ 50 ちゅ〜る！", line.text
    assert_equal :happy, line.face
    assert line.bounce

    assert_equal "オルカさんからミケさんへの振込、ぶじに終わったにゃ！", for_staff.line(last(Banking::Events::TransferCompleted)).text
    assert_equal "オルカさんの口座に 1,000 ちゅ〜る 入金にゃ！", for_staff.line(last(Banking::Events::MoneyDeposited)).text
  end

  test "利用者の画面: 自分は「あなた」、相手は「ほかのお客さま」。他人の名前は出さない" do
    requested = last(Banking::Events::TransferRequested)
    assert_equal "いまあなたからほかのお客さまへ 50 ちゅ〜る！", for_customer(@orca).line(requested).text
    assert_equal "いまほかのお客さまからあなたへ 50 ちゅ〜る！", for_customer(@mike).line(requested).text

    credited = last(Banking::Events::TransferCredited)
    text = for_customer(@mike).line(credited).text
    assert_equal "ほかのお客さまからあなたへ、50 ちゅ〜る とどいたにゃ！", text
    assert_not_includes text, "オルカ"

    # 口座が2つあれば、どちらの口座か添える
    assert_includes for_customer(@orca, "9999999").line(requested).text, "あなた（口座 #{@orca}）"
  end

  test "行員の名前は、行員の画面だけ" do
    event = Approvals::Events::ApprovalGranted.new(data: { approval_id: "a1", approved_by: @tama.actor })
    assert_includes for_staff.line(event).text, "窓口のたま"
    assert_not_includes for_customer(@orca).line(event).text, "たま"
  end

  test "商店の口座は、利用者の画面でも商店の名前" do
    shop = Banking::Bank.new(actor: "test").open_account(holder_name: Shop::Store::SHOP_NAME).account_number
    event = Banking::Events::TransferRequested.new(data: { transfer_id: "t1", from_account: @orca, to_account: shop, amount: 120 })
    assert_equal "いまあなたから#{Shop::Store::SHOP_NAME}へ 120 ちゅ〜る！", for_customer(@orca).line(event).text
  end

  test "知らない出来事は、日本語の名前で" do
    unknown = Class.new(RubyEventStore::Event) { def self.name = "Mystery::Happened" }.new(data: {})
    line = for_staff.line(unknown)
    assert_equal "Happenedがあったにゃ", line.text
    assert_equal :normal, line.face
  end

  test "ねこ町の住民（metadata の resident）がした出来事は、だれの仕業かを頭に付ける" do
    event_store.with_metadata(resident: "こむぎ") { Banking::Bank.new(actor: "customer:9").deposit(@mike, 7) }
    resident_line = for_staff.line(last(Banking::Events::MoneyDeposited))
    assert resident_line.text.start_with?("［住民のこむぎ］"), resident_line.text

    Banking::Bank.new(actor: @tama.actor).deposit(@mike, 8)
    assert_not for_staff.line(last(Banking::Events::MoneyDeposited)).text.start_with?("［住民")
  end
end
