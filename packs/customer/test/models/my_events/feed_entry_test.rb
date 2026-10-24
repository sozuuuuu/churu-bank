require "test_helper"

# 「わたしの出来事」の索引: 出来事1件を、見てよい口座ぶん1行ずつ。一覧は新しい順に区切って読む
class MyEvents::FeedEntryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @bank = Banking::Bank.new(actor: "test")
    perform_enqueued_jobs do # 索引の係（FeedJob）はコミットのあとに Solid Queue で動く
      @a = @bank.open_account(holder_name: "オルカ").account_number
      @b = @bank.open_account(holder_name: "ジンジベル").account_number
    end
  end

  def event_store = Rails.configuration.event_store

  def types(number) = MyEvents::FeedEntry.where(account_number: number).pluck(:event_type).map(&:demodulize)

  test "振込の引き落としは振込元だけ、入金は振込先だけ、受付と完了は両方の口座に書く" do
    perform_enqueued_jobs do
      @bank.deposit(@a, 100)
      @bank.transfer(@a, @b, 30)
    end

    assert_includes types(@a), "TransferDebited"
    assert_not_includes types(@b), "TransferDebited"
    assert_includes types(@b), "TransferCredited"
    assert_not_includes types(@a), "TransferCredited"
    %w[TransferRequested TransferCompleted].each do |type|
      assert_includes types(@a), type
      assert_includes types(@b), type
    end
  end

  test "ちゅ〜るローンの出来事も、借りた口座に書く" do
    perform_enqueued_jobs { @bank.lend(@a, 100) }

    assert_equal %w[AccountOpened LoanDisbursed LoanGranted].sort, types(@a).sort
    assert_equal %w[AccountOpened], types(@b)
  end

  test "何度書いても増えない。作り直すと同じになる" do
    perform_enqueued_jobs { @bank.deposit(@a, 100) }
    event = event_store.read.of_type(Banking::Events::MoneyDeposited).last
    MyEvents::FeedEntry.record(event)
    assert_equal 1, MyEvents::FeedEntry.where(event_id: event.event_id).count

    before = MyEvents::FeedEntry.order(:account_number, :event_id).pluck(:account_number, :event_id)
    MyEvents::FeedEntry.rebuild!
    assert_equal before, MyEvents::FeedEntry.order(:account_number, :event_id).pluck(:account_number, :event_id)
  end

  test "ページ: 新しい順に区切り、同じ出来事が自分の口座2つにかかわっても1回だけ" do
    perform_enqueued_jobs do
      @bank.deposit(@a, 100)
      5.times { @bank.transfer(@a, @b, 1) } # 受付と完了は両方の口座の行がある
    end

    all = []
    cursor = nil
    loop do
      rows, cursor = MyEvents::FeedEntry.page([ @a, @b ], before: cursor, limit: 4)
      all.concat(rows)
      break unless cursor
    end
    ids = all.map(&:event_id)
    assert_equal ids.uniq, ids, "同じ出来事は1回だけ"
    assert_equal MyEvents::FeedEntry.distinct.count(:event_id), ids.size
    assert_equal all.map(&:recorded_at), all.map(&:recorded_at).sort.reverse
    assert_match(/\A\d+_\d+\z/, MyEvents::FeedEntry.encode(all.first), "印は数字だけ")
  end
end
