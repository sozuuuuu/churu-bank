require "test_helper"

# ふせんの壁の組み立て: 処理（だれ・命令・出来事）に分け、つながる処理を1本の流れにし、続きが来ていないところを見つける
class EventViewer::WallTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @bank = Banking::Bank.new(actor: "customer:1")
    @staff = Banking::Bank.new(actor: "staff:1")
    @orca = @staff.open_account(holder_name: "オルカ").account_number
    @zingiber = @staff.open_account(holder_name: "ジンジベル").account_number
    @staff.deposit(@orca, 1000)
    drain
  end

  # ジョブが次のジョブを積む（振込の入金 → 商店の引き当て → 返金 …）ので、空になるまで流す
  def drain
    10.times do
      break if enqueued_jobs.empty?

      perform_enqueued_jobs
    end
  end

  def event_store = Rails.configuration.event_store
  def wall(**) = EventViewer::Wall.new(**)
  def row_of(wall, stream) = wall.matching.find { |row| row.events.any? { EventLens::EventIndex.keys(it).include?(stream) } }
  def labels(events) = events.map { EventLens::Catalog.entry(it.event_type).label }
  # [だれ（人の actor か 係の名前）, 命令, 出来事, きっかけ, 抜け]
  def beats(row) = row.beats.map { [ it.policy&.label || it.actor, it.command, labels(it.events), it.cause && labels([ it.cause ]).first, it.waiting ] }

  test "振込: 利用者が「振り込む」→ 引き落としが来たので、振込の確定の係が入金する" do
    transfer_id = @bank.transfer(@orca, @zingiber, 50).transfer_id
    drain

    row = row_of(wall, "Transfer$#{transfer_id}")
    assert_equal [
      [ "customer:1", "振り込む", %w[振込の引き落とし 振込の受付], nil, nil ],
      [ "振込の確定の係", "振込先へ入金する", %w[振込の入金 振込の完了], "振込の引き落とし", nil ]
    ], beats(row)
    assert row.beats.first.person?
    assert_not row.beats.last.person?
    assert_equal "Transfer$#{transfer_id}", row.business_key
  end

  test "流れの抜け: ジョブがまだ動いていない振込・保留中・予約中にはピンクのふせん。保留を通せば消える" do
    pending = @bank.transfer(@orca, @zingiber, 10).transfer_id # ジョブを流さない
    assert_equal "続きの出来事がまだありません（振込の確定の係が動いていない？）", row_of(wall, "Transfer$#{pending}").beats.first.waiting
    drain

    held = @bank.transfer(@orca, @zingiber, Banking::Bank.hold_threshold).transfer_id
    drain
    row = row_of(wall, "Transfer$#{held}")
    assert_equal "保留中: 行員が確かめて「通す」のを待っています", row.beats.first.waiting
    assert row.waiting?

    @staff.release_transfer(held)
    drain
    row = row_of(wall, "Transfer$#{held}")
    assert_equal [
      [ "customer:1", "振り込む", %w[振込の引き落とし 振込の受付 振込の保留], nil, nil ],
      [ "staff:1", "保留を通す", %w[保留を通す], nil, nil ],
      [ "振込の確定の係", "振込先へ入金する", %w[振込の入金 振込の完了], "保留を通す", nil ]
    ], beats(row)
    assert_not row.waiting?

    scheduled = @bank.transfer(@orca, @zingiber, 5, execute_on: Date.current + 3).transfer_id
    assert_match(/\A予約中: 実行日（#{Date.current + 3}）を待っています\z/, row_of(wall, "Transfer$#{scheduled}").beats.first.waiting)
  end

  test "お買いもの: 注文 → 振込の確定の係 → 商店の支払いの係（返金を頼む）→ … まで1本。注文が見出し" do
    store = Shop::Store.new(actor: "customer:1")
    store.open_shop
    sku = "test-tsumetogi-#{SecureRandom.hex(3)}" # seeds（db:seed:replant）の商品とぶつからないように
    store.register_product(sku:, name: "爪とぎ", price: 300)
    store.restock(sku, 1)
    order_id = SecureRandom.uuid
    store.place_order(order_id:, buyer_account: @orca, items: { sku => 2 })
    drain

    row = row_of(wall, "Order$#{order_id}")
    assert_equal [
      [ "customer:1", "注文する", %w[振込の引き落とし 振込の受付 注文 支払いの依頼], nil, nil ],
      [ "振込の確定の係", "振込先へ入金する", %w[振込の入金 振込の完了], "振込の引き落とし", nil ],
      [ "商店の支払いの係", "注文をキャンセルして返金を頼む", %w[振込の引き落とし 振込の受付 支払いの完了 注文のキャンセル 返金の依頼], "振込の完了", nil ],
      [ "振込の確定の係", "振込先へ入金する", %w[振込の入金 振込の完了], "振込の引き落とし", nil ],
      [ "商店の支払いの係", "返金を確かめる", %w[返金の完了], "振込の完了", nil ]
    ], beats(row)
    assert_equal "Order$#{order_id}", row.business_key, "頼む側（注文）を見出しに"
    assert_not row.waiting?
  end

  test "入金の取消: まちがえた入金 → 申請 → 承認が、取り消す通帳の行でつながって1本になる" do
    travel 2.seconds # 準備の入金とは別の処理に（travel は秒より下を切り捨てるので 2 秒）
    mistake = @staff.deposit(@zingiber, 100, memo: "まちがい").events.first
    travel 2.seconds
    submitted = Approvals::Desk.new(actor: "staff:1").request_reversal(@zingiber, mistake.event_id, reason: "金額まちがい")
    Approvals::Desk.new(actor: "staff:2").approve(submitted.approval_id)

    row = wall.matching.find { |r| r.events.any? { it.event_id == mistake.event_id } }
    assert_equal [ [ "staff:1", "入金する" ], [ "staff:1", "承認を申請する" ], [ "staff:2", "承認する" ] ],
                 row.beats.map { [ it.actor, it.command ] }
    assert_includes labels(row.beats.last.events), "入金の取消"
  end

  test "同じ人が続けて出金を2回頼んでも、依頼ごとに別の流れ" do
    @bank.request_withdrawal(@orca, 30)
    @bank.request_withdrawal(@orca, 10)
    request_rows = wall(kind: "request").matching.select { |row| labels(row.events) == %w[出金の依頼] }
    assert_operator request_rows.size, :>=, 2
  end

  test "絞り込み: ひとつながり（correlation）・期間・種類。種類に合わない出来事は薄くする" do
    transfer_id = @bank.transfer(@orca, @zingiber, 50).transfer_id
    drain
    debited = event_store.read.of_type(Banking::Events::TransferDebited).last

    only = wall(correlation: debited.correlation_id)
    assert_equal 1, only.matching.size
    assert_includes only.matching.first.events.map(&:event_id), debited.event_id
    assert only.filtered?

    assert row_of(wall(from: Date.current.iso8601, to: Date.current.iso8601), "Transfer$#{transfer_id}")
    assert_nil row_of(wall(to: Date.yesterday.iso8601), "Transfer$#{transfer_id}")
    assert_nil row_of(wall(from: Date.tomorrow.iso8601), "Transfer$#{transfer_id}")

    money_in = wall(kind: "money_in")
    row = row_of(money_in, "Transfer$#{transfer_id}")
    assert row, "振込の入金（money_in）がある流れは残る"
    credited, completed = row.beats.last.events
    assert money_in.highlighted?(credited)
    assert_not money_in.highlighted?(completed)
    assert_nil row_of(wall(kind: "shop"), "Transfer$#{transfer_id}")

    assert_not wall(kind: "nanika", from: "きのう").filtered?, "知らない種類・読めない日付は無視"
  end

  test "いつもの流れ: 同じ並びの流れ（だれが・何を頼み・どの出来事）をまとめて数える。人の名前はちがってよい" do
    first = @bank.transfer(@orca, @zingiber, 10).transfer_id
    drain
    travel 1.second
    second = Banking::Bank.new(actor: "customer:2").transfer(@orca, @zingiber, 20).transfer_id
    drain

    built = wall
    pattern = built.patterns.find { |p| p.rows.include?(row_of(built, "Transfer$#{first}")) }
    assert_includes pattern.rows, row_of(built, "Transfer$#{second}")
    assert_equal row_of(built, "Transfer$#{second}"), pattern.sample, "ふせんは新しいほうの流れ"
    assert_equal [ [ "customer", "振り込む", %w[Banking::Events::TransferDebited Banking::Events::TransferRequested] ],
                   [ "振込の確定の係", "振込先へ入金する", %w[Banking::Events::TransferCredited Banking::Events::TransferCompleted] ] ],
                 pattern.sample.signature
    assert_equal built.patterns.map(&:count).sort.reverse, built.patterns.map(&:count), "多い順"
  end

  test "命令のことば: 表にない出来事は「〜」を起こす" do
    assert_equal "振り込む", EventViewer::WallWords.command([ Banking::Events::TransferRequested.new(data: {}) ])
    assert_equal "注文する", EventViewer::WallWords.command([ Banking::Events::TransferDebited.new(data: {}), Shop::Events::OrderPlaced.new(data: {}) ])
    unknown = Class.new(RubyEventStore::Event) { def self.name = "Nanika::Happened" }
    assert_equal "「Happened」を起こす", EventViewer::WallWords.command([ unknown.new ])
  end
end
