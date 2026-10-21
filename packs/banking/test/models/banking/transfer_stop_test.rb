require "test_helper"

# 振込の差し止め（TODO の Q3）: 予約振込、高額振込の保留、実行前の取消（利用者）・差し止め（行員）
class Banking::TransferStopTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @bank = Banking::Bank.new(actor: "test")
    @orca = @bank.open_account(holder_name: "オルカ").account_number
    @zingiber = @bank.open_account(holder_name: "ジンジベル").account_number
    @bank.deposit(@orca, 1000)
    @threshold = Banking::Bank.hold_threshold
  end

  def event_store = Rails.configuration.event_store
  def balance(number) = Account.find_by!(number:).balance
  def transfer(id) = Transfer.find_by!(transfer_id: id)
  def tomorrow = Date.current + 1
  def settle = perform_enqueued_jobs(only: Transfers::SettleJob)
  def types(events) = events.map { it.class.name.demodulize }

  # ---- 予約振込 ----

  test "予約振込は受付だけして、引き落とさない" do
    outcome = @bank.transfer(@orca, @zingiber, 30, memo: "家賃", execute_on: tomorrow)

    assert_equal [ 1000, 1000 ], [ outcome.balance_before, outcome.balance_after ]
    assert_equal %w[TransferScheduled], types(outcome.events)
    assert_match "引き落として振り込みます", outcome.warnings.first
    t = transfer(outcome.transfer_id)
    assert_equal [ "scheduled", "予約中", tomorrow ], [ t.status, t.status_label, t.execute_on ]
    assert_equal 1000, balance(@orca)
    assert_empty LedgerEntry.where(account_number: @orca, kind: "transfer_out")
    assert_no_enqueued_jobs only: Transfers::SettleJob
  end

  test "実行日になると引き落とされ、ジョブで入金されて完了する" do
    id = @bank.transfer(@orca, @zingiber, 30, execute_on: tomorrow).transfer_id

    assert_empty @bank.execute_due_transfers(date: Date.current), "実行日の前は何もしない"
    assert_equal "scheduled", transfer(id).status

    travel_to(tomorrow.in_time_zone.change(hour: 0, min: 1)) do
      perform_enqueued_jobs(only: Transfers::ExecuteDueJob) { Transfers::ExecuteDueJob.perform_later }
    end
    assert_equal "requested", transfer(id).status
    assert_equal 970, balance(@orca)

    settle
    assert_equal "completed", transfer(id).status
    assert_equal 30, balance(@zingiber)
    assert_equal %w[TransferScheduled TransferStarted TransferDebited TransferCompleted TransferCredited],
                 types(event_store.read.stream("Transfer$#{id}").to_a)
  end

  test "予約の実行は何度動いても1回分だけ" do
    id = @bank.transfer(@orca, @zingiber, 30, execute_on: tomorrow).transfer_id

    2.times { @bank.execute_due_transfers(date: tomorrow) }
    assert_nil @bank.execute_transfer(id, date: tomorrow)

    assert_equal 970, balance(@orca)
    assert_equal 1, LedgerEntry.where(account_number: @orca, kind: "transfer_out").count
  end

  test "実行日に残高が足りなければ「実行できず」で、お金は動かない" do
    @bank.transfer(@orca, @zingiber, 30, execute_on: tomorrow) # 先に予約しておく
    outcome = @bank.transfer(@orca, @zingiber, 2000, execute_on: tomorrow)
    assert_match "残高", outcome.warnings.join

    @bank.execute_due_transfers(date: tomorrow)

    t = transfer(outcome.transfer_id)
    assert_equal [ "unexecuted", "実行できず" ], [ t.status, t.status_label ]
    assert_match "残高不足", t.failure_reason
    assert_equal 970, balance(@orca), "ほかの予約は実行される"
  end

  test "実行日は明日以降・1年以内。予約でも振込元は使える口座でないといけない" do
    assert_raises(ArgumentError) { @bank.transfer(@orca, @zingiber, 30, execute_on: Date.current) }
    assert_raises(ArgumentError) { @bank.transfer(@orca, @zingiber, 30, execute_on: Date.current - 1) }
    assert_raises(ArgumentError) { @bank.transfer(@orca, @zingiber, 30, execute_on: Date.current + 400) }
    assert_raises(ArgumentError) { @bank.transfer(@orca, @zingiber, 30, execute_on: "あした") }
    assert_raises(ArgumentError) { @bank.transfer(@orca, @orca, 30, execute_on: tomorrow) }
    @bank.freeze_account(@orca, reason: "テスト")
    assert_raises(Banking::InvalidState) { @bank.transfer(@orca, @zingiber, 30, execute_on: tomorrow) }
    assert_equal 0, Transfer.count
  end

  # ---- 取消（利用者） ----

  test "予約中に取り消すと、お金は動かずに取消済みになる" do
    id = @bank.transfer(@orca, @zingiber, 30, execute_on: tomorrow).transfer_id

    preview = @bank.cancel_transfer(id, from: @orca, dry_run: true)
    assert_equal %w[TransferCancelled], types(preview.events)
    assert_equal "scheduled", transfer(id).status

    @bank.cancel_transfer(id, from: @orca)
    t = transfer(id)
    assert_equal [ "cancelled", "取消済み", "test" ], [ t.status, t.status_label, t.cancelled_by ]
    assert_equal 1000, balance(@orca)

    @bank.execute_due_transfers(date: tomorrow)
    assert_equal "cancelled", transfer(id).status, "取り消した予約は実行されない"
    assert_equal 1000, balance(@orca)
  end

  test "保留中に取り消すと、引き落としたお金が戻る" do
    outcome = @bank.transfer(@orca, @zingiber, @threshold)
    assert_equal 1000 - @threshold, balance(@orca)

    result = @bank.cancel_transfer(outcome.transfer_id, from: @orca)

    assert_equal %w[TransferRefunded TransferCancelled], types(result.events)
    assert_equal [ 1000 - @threshold, 1000 ], [ result.balance_before, result.balance_after ]
    assert_equal 1000, balance(@orca)
    assert_equal %w[deposit transfer_out transfer_refund], LedgerEntry.where(account_number: @orca).order(:id).pluck(:kind)
    settle
    assert_equal 0, balance(@zingiber)
  end

  test "二重に取り消せない" do
    id = @bank.transfer(@orca, @zingiber, @threshold).transfer_id
    @bank.cancel_transfer(id, from: @orca)

    error = assert_raises(Banking::InvalidState) { @bank.cancel_transfer(id, from: @orca) }
    assert_match "取消済み", error.message
    assert_raises(Banking::InvalidState) { @bank.stop_transfer(id, reason: "念のため") }
    assert_equal 1000, balance(@orca), "二重に払い戻さない"
  end

  test "実行が始まった（処理中・完了の）振込は取り消せない" do
    id = @bank.transfer(@orca, @zingiber, 30).transfer_id
    error = assert_raises(Banking::InvalidState) { @bank.cancel_transfer(id, from: @orca) }
    assert_match "実行が始まっている", error.message

    settle
    assert_raises(Banking::InvalidState) { @bank.cancel_transfer(id, from: @orca) }
    assert_equal "completed", transfer(id).status
  end

  test "他人の口座からの振込は取り消せない（ないものとして NotFound）" do
    id = @bank.transfer(@orca, @zingiber, 30, execute_on: tomorrow).transfer_id

    assert_raises(Banking::NotFound) { @bank.cancel_transfer(id, from: @zingiber) }
    assert_raises(Banking::NotFound) { @bank.cancel_transfer(SecureRandom.uuid) }
    assert_equal "scheduled", transfer(id).status
  end

  test "実行と取消がぶつかったら、expected_version で後から来た方が負ける" do
    id = @bank.transfer(@orca, @zingiber, 30, execute_on: tomorrow).transfer_id

    # 取消の側が予約中の振込を読んだあと、先に予約が実行された
    canceller = Banking::Bank.new(actor: "test")
    stale = canceller.send(:load_transfer, id)
    canceller.define_singleton_method(:load_transfer) { |_id| stale }
    @bank.execute_transfer(id, date: tomorrow)

    assert_raises(Banking::ConcurrentModification) { canceller.cancel_transfer(id, from: @orca) }
    assert_equal "requested", transfer(id).status
    assert_equal 970, balance(@orca), "取消の払い戻しも書かれない"
    settle
    assert_equal "completed", transfer(id).status
  end

  test "取消と実行がぶつかったら、実行のほうが負けて、取消済みのまま" do
    id = @bank.transfer(@orca, @zingiber, 30, execute_on: tomorrow).transfer_id

    executor = Banking::Bank.new(actor: "transfer-scheduler")
    stale = executor.send(:load_transfer, id)
    executor.define_singleton_method(:load_transfer) { |_id| stale }
    @bank.cancel_transfer(id, from: @orca)

    assert_raises(Banking::ConcurrentModification) { executor.execute_transfer(id, date: tomorrow) }
    assert_empty executor.execute_due_transfers(date: tomorrow), "まとめて実行するときは負けた振込を飛ばす"
    assert_equal "cancelled", transfer(id).status
    assert_equal 1000, balance(@orca), "引き落としも書かれない"
  end

  # ---- 高額振込の保留（行員が通す・差し止める） ----

  test "しきい値以上の振込は引き落としたあと保留になり、入金されない" do
    outcome = @bank.transfer(@orca, @zingiber, @threshold)

    assert_equal %w[TransferDebited TransferRequested TransferHeld], types(outcome.events)
    assert_match "保留", outcome.warnings.join
    settle
    t = transfer(outcome.transfer_id)
    assert_equal [ "held", "保留中" ], [ t.status, t.status_label ]
    assert t.held_at
    assert_equal 0, balance(@zingiber)

    assert_equal "requested", Transfer.find_by!(transfer_id: @bank.transfer(@orca, @zingiber, @threshold - 1).transfer_id).status
  end

  test "保留を通すと入金されて完了する" do
    id = @bank.transfer(@orca, @zingiber, @threshold).transfer_id
    settle

    preview = @bank.release_transfer(id, dry_run: true)
    assert_equal [ @zingiber, 0, @threshold ], [ preview.account_number, preview.balance_before, preview.balance_after ]
    assert_equal "held", transfer(id).status

    @bank.release_transfer(id)
    assert_equal "requested", transfer(id).status
    settle
    assert_equal "completed", transfer(id).status
    assert_equal @threshold, balance(@zingiber)
    assert_raises(Banking::InvalidState) { @bank.release_transfer(id) }
  end

  test "保留を差し止めると、振込元へお金が戻る。理由は必須" do
    id = @bank.transfer(@orca, @zingiber, @threshold).transfer_id

    assert_raises(ArgumentError) { @bank.stop_transfer(id, reason: " ") }
    @bank.stop_transfer(id, reason: "詐欺の疑い")

    t = transfer(id)
    assert_equal [ "stopped", "差し止め", "詐欺の疑い" ], [ t.status, t.status_label, t.cancel_reason ]
    assert_equal 1000, balance(@orca)
    assert_equal "詐欺の疑い", LedgerEntry.where(account_number: @orca).last.memo
    settle
    assert_equal 0, balance(@zingiber)
    assert_raises(Banking::InvalidState) { @bank.release_transfer(id) }
  end

  test "高額の予約振込は、実行日に引き落としたあと保留になる。予約中のうちに差し止めもできる" do
    held = @bank.transfer(@orca, @zingiber, @threshold, execute_on: tomorrow)
    assert_match "実行日に引き落としたあと", held.warnings.join
    stopped = @bank.transfer(@orca, @zingiber, 10, execute_on: tomorrow).transfer_id
    @bank.stop_transfer(stopped, reason: "名義の確認")

    @bank.execute_due_transfers(date: tomorrow)
    settle

    assert_equal "held", transfer(held.transfer_id).status
    assert_equal "stopped", transfer(stopped).status
    assert_equal 1000 - @threshold, balance(@orca)
  end

  test "商店の支払いのように holdable: false なら保留しない" do
    id = @bank.transfer(@orca, @zingiber, @threshold, holdable: false).transfer_id
    settle
    assert_equal "completed", transfer(id).status
  end

  # 口座側のお金の動きは、振込の集約のイベントのあとにリンクされる
  test "差し止め・取消のイベントも Transfer$ から辿れる" do
    id = @bank.transfer(@orca, @zingiber, @threshold).transfer_id
    @bank.stop_transfer(id, reason: "テスト")

    assert_equal %w[TransferRequested TransferHeld TransferDebited TransferStopped TransferRefunded],
                 types(event_store.read.stream("Transfer$#{id}").to_a)
  end
end
