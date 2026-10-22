require "test_helper"

# つながりの図の組み立て: correlation_id / causation_id と、同じ振込・注文などのストリームから「ひとつながり」を集め、
# 処理（Step）に分けて、きっかけ（:cause）・そのあと（:then）でつなぐ
class EventLens::FlowTest < ActiveSupport::TestCase
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

  def labels(events) = events.map { EventLens::Catalog.entry(it.event_type).label }
  def steps(flow) = flow.steps.map { [ labels(it.events), it.edge, it.depth ] }

  test "振込: 受付の処理 → きっかけ → ジョブの入金と完了。どの出来事から開いても同じ1本" do
    transfer_id = @bank.transfer(@orca, @zingiber, 50).transfer_id
    drain

    flow = EventLens::Flow.of_stream("Transfer$#{transfer_id}")
    assert_equal [
      [ %w[振込の引き落とし 振込の受付], nil, 0 ],
      [ %w[振込の入金 振込の完了], :cause, 1 ]
    ], steps(flow)

    debited, requested, credited, completed = flow.events
    assert_equal :same, flow.link_to(requested.event_id).kind
    assert_equal [ debited.event_id, :cause ], flow.link_to(credited.event_id).then { [ it.from, it.kind ] }
    assert_equal [ credited.event_id, :same ], flow.link_to(completed.event_id).then { [ it.from, it.kind ] }
    assert_nil flow.link_to(debited.event_id)

    from_end = EventLens::Flow.around(completed.event_id)
    assert_equal flow.events.map(&:event_id), from_end.events.map(&:event_id)
    assert_equal [ "Account$#{@orca}", "Transfer$#{transfer_id}", "Account$#{@zingiber}" ], flow.lanes
  end

  test "振込先が凍結中なら組戻し（払い戻しと失敗）" do
    @staff.freeze_account(@zingiber, reason: "テスト")
    transfer_id = @bank.transfer(@orca, @zingiber, 20).transfer_id
    drain

    flow = EventLens::Flow.of_stream("Transfer$#{transfer_id}")
    assert_equal [
      [ %w[振込の引き落とし 振込の受付], nil, 0 ],
      [ %w[振込の払い戻し 振込の失敗（組戻し）], :cause, 1 ]
    ], steps(flow)
  end

  test "高額振込の保留: 行員が通した処理は「そのあと」でつながり、そこから入金が続く" do
    transfer_id = @bank.transfer(@orca, @zingiber, Banking::Bank.hold_threshold).transfer_id
    drain
    @staff.release_transfer(transfer_id)
    drain

    flow = EventLens::Flow.of_stream("Transfer$#{transfer_id}")
    assert_equal [
      [ %w[振込の引き落とし 振込の受付 振込の保留], nil, 0 ],
      [ %w[保留を通す], :then, 0 ],
      [ %w[振込の入金 振込の完了], :cause, 1 ]
    ], steps(flow)
    assert_equal flow.steps[0].events.last.event_id, flow.steps[1].parent_id
  end

  test "お買いもの: 注文 → 振込 → 引き当て、在庫が足りなければ返金まで1本の流れ" do
    store = Shop::Store.new(actor: "customer:1")
    store.open_shop
    sku = "test-tsumetogi-#{SecureRandom.hex(3)}" # seeds（db:seed:replant）の商品とぶつからないように
    store.register_product(sku:, name: "爪とぎ", price: 300)
    store.restock(sku, 1)
    order_id = SecureRandom.uuid
    store.place_order(order_id:, buyer_account: @orca, items: { sku => 2 })
    drain

    flow = EventLens::Flow.of_stream("Order$#{order_id}")
    assert_equal [
      [ %w[振込の引き落とし 振込の受付 注文 支払いの依頼], nil, 0 ],
      [ %w[振込の入金 振込の完了], :cause, 1 ],
      [ %w[振込の引き落とし 振込の受付 支払いの完了 注文のキャンセル 返金の依頼], :cause, 2 ],
      [ %w[振込の入金 振込の完了], :cause, 3 ],
      [ %w[返金の完了], :cause, 4 ]
    ], steps(flow)
    assert_equal "Order$#{order_id}", flow.lanes.first, "頼む側（注文）がいちばん左"
  end

  test "出金依頼と二人承認も、申請・依頼から実行までが1本になる" do
    request_id = @bank.request_withdrawal(@orca, 30).request_id
    @staff.process_withdrawal(request_id)
    flow = EventLens::Flow.of_stream("WithdrawalRequest$#{request_id}")
    assert_equal [ [ %w[出金の依頼], nil, 0 ], [ %w[出金（窓口） 出金依頼の処理], :then, 0 ] ], steps(flow)

    @staff.freeze_account(@zingiber, reason: "テスト")
    submitted = Approvals::Desk.new(actor: "staff:1").request_unfreeze(@zingiber, reason: "確認できた")
    Approvals::Desk.new(actor: "staff:2").approve(submitted.approval_id)
    flow = EventLens::Flow.of_stream("Approval$#{submitted.approval_id}")
    assert_equal [ [ %w[承認の申請], nil, 0 ], [ %w[凍結の解除 承認 承認した操作の実行], :then, 0 ] ], steps(flow)
    assert_not_includes labels(flow.events), "口座の凍結", "口座のストリームはたどらない（出来事が多すぎるため）"
  end

  test "ない出来事は NotFound" do
    assert_raises(EventLens::Flow::NotFound) { EventLens::Flow.around(SecureRandom.uuid) }
    assert_raises(EventLens::Flow::NotFound) { EventLens::Flow.of_stream("Transfer$nothing") }
  end

  test "図の座標: きっかけは1列右、処理の中はまっすぐ下" do
    transfer_id = @bank.transfer(@orca, @zingiber, 50).transfer_id
    drain
    flow = EventLens::Flow.of_stream("Transfer$#{transfer_id}")
    tree = EventLens::Diagram::Tree.new(flow)

    xs = tree.nodes.map(&:x)
    assert_equal [ xs[0], xs[0], xs[0] + EventLens::Diagram::Tree::COL, xs[0] + EventLens::Diagram::Tree::COL ], xs
    assert_equal tree.nodes.map(&:y).sort, tree.nodes.map(&:y), "上から下へ時間が進む"
    assert_equal [ 0, 1, 2, 3 ], tree.nodes.map(&:order)
    assert_equal %i[same cause same], tree.edges.map(&:kind)

    lanes = EventLens::Diagram::Lanes.new(flow)
    assert_equal 3, lanes.lanes.size
    assert_equal tree.nodes.size, lanes.nodes.size
  end
end
