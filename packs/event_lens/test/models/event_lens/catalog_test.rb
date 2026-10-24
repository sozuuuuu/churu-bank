require "test_helper"

# イベントの日本語名の足し忘れを見つける。新しいイベントのクラスを作ったら、EventLens::Catalog::ROWS にも1行足す
class EventLens::CatalogTest < ActiveSupport::TestCase
  def all_event_classes
    Rails.application.eager_load!
    RubyEventStore::Event.descendants.select { it.name&.match?(/\A(Banking|Shop|Approvals)::Events::/) }
  end

  test "銀行・商店・二人承認のすべてのイベントに、日本語の名前・種類・アイコン・説明がある" do
    classes = all_event_classes
    assert_operator classes.size, :>=, 47

    missing = classes.map(&:name).reject { EventLens::Catalog::ENTRIES.key?(it) }
    assert_empty missing, "日本語の名前がないイベント: #{missing.join(', ')}"

    EventLens::Catalog::ENTRIES.each_value do |entry|
      assert entry.label.present?
      assert entry.description.present?, entry.type
      assert EventLens::Catalog::KINDS.key?(entry.kind), "#{entry.type} の種類 #{entry.kind}"
      assert Ui::ThemeHelper::ICONS.key?(entry.icon), "#{entry.type} のアイコン #{entry.icon}"
    end
  end

  test "名前はぶつからない（ちがう出来事が同じ日本語にならない）" do
    labels = EventLens::Catalog::ENTRIES.values.map(&:label)
    assert_equal labels.uniq.size, labels.size, labels.tally.select { |_, n| n > 1 }.keys.inspect
  end

  test "すべてのイベントに、もともと書かれるストリームが決まっている（レーン図の関係者）" do
    all_event_classes.each do |klass|
      event = klass.new(data: { account_number: "0000001", transfer_id: "t", request_id: "r", approval_id: "a", sku: "s", order_id: "o", loan_id: "l" })
      assert_match(/\A(Account|Transfer|WithdrawalRequest|Loan|Approval|Shop|Product|Order)\$./, EventLens::Catalog.home_stream(event).to_s,
                   "#{klass.name} のストリーム")
    end
  end

  test "知らないイベントでも落ちずに「そのほか」で出す" do
    entry = EventLens::Catalog.entry("Someday::Events::Unknown")
    assert_equal "Unknown", entry.label
    assert_equal "そのほか", entry.kind_label
  end
end
