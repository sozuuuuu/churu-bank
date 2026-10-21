require "test_helper"

class Notices::InboxTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @board = Notices::Board.new(actor: "test")
    @orca = create_customer(name: "オルカ")
    @mike = create_customer(name: "ミケ")
  end

  test "掲載期間の外（始まる前・終わった後）は出ない" do
    live = @board.post(kind: "info", title: "いま")
    @board.post(kind: "info", title: "あした", starts_at: 1.day.from_now)
    @board.post(kind: "info", title: "きのうまで", starts_at: 3.days.ago, ends_at: 1.day.ago)

    assert_equal [ live ], Notices::Inbox.new(@orca).notices
  end

  test "選んだ利用者向けは、その人にだけ出る" do
    only_orca = @board.post(kind: "request", title: "オルカさんへ", customers: [ @orca ])

    assert_equal "selected", only_orca.audience
    assert_includes Notices::Inbox.new(@orca).notices, only_orca
    assert_empty Notices::Inbox.new(@mike).notices
  end

  test "開いたら既読。ふつうのものは吹き出しから消えるが、重要なものは閉じるまで出る" do
    normal = @board.post(kind: "info", title: "ふつう")
    important = @board.post(kind: "request", title: "だいじ", important: true)
    assert_equal 2, Notices::Inbox.new(@orca).unread_count

    NoticeReceipt.read!(normal, @orca)
    NoticeReceipt.read!(important, @orca)
    inbox = Notices::Inbox.new(@orca)
    assert_equal 0, inbox.unread_count
    assert_equal [ important ], inbox.bubble

    NoticeReceipt.dismiss!(important, @orca)
    assert_empty Notices::Inbox.new(@orca).bubble
    assert_equal 2, Notices::Inbox.new(@mike).unread_count # ほかの人の既読には関係ない
  end

  test "掲載終了したものは出ない。始まる前のものを終えても、終わりが始まりより前にならない" do
    live = @board.post(kind: "info", title: "いま")
    later = @board.post(kind: "info", title: "あした", starts_at: 1.day.from_now)

    @board.close(live)
    @board.close(later)

    assert_empty Notices::Inbox.new(@orca).notices
    assert later.reload.ended?
    assert_operator later.starts_at, :<=, later.ends_at
  end

  test "出したら、開いている利用者画面に refresh を送る。始まりが先なら、その時刻にも" do
    assert_enqueued_jobs 2, only: Notices::RefreshJob do
      @board.post(kind: "maintenance", title: "あしたメンテ", starts_at: 1.day.from_now)
    end
  end

  test "入力がまちがっていたら保存しない（対象を選ばない・終わりが始まりより前・タイトルなし）" do
    assert_no_difference "Notice.count" do
      assert_not @board.post(kind: "info", title: "だれにも", audience: "selected", target_customer_ids: [ "" ]).persisted?
      assert_not @board.post(kind: "info", title: "逆", starts_at: 1.day.from_now, ends_at: Time.current).persisted?
      assert_not @board.post(kind: "info", title: "").persisted?
      assert_not @board.post(kind: "campaign", title: "まだない種類").persisted?
    end
  end
end
