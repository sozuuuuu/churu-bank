require "test_helper"

# 利用者のねこの実況: 出来事を見てよい利用者にだけ、他人の名前・行員の名前を出さない文で配信する
class MyEvents::CommentaryJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  setup do
    @tama = create_staff(name: "窓口のたま")
    @kuro = create_staff(name: "係長のくろ")
    @orca = create_customer(name: "オルカ")
    @zingiber = create_customer(name: "ジンジベル")
    @bank = Banking::Bank.new(actor: @tama.actor)
    @mine = @bank.open_account(holder_name: "オルカ").account_number
    @theirs = @bank.open_account(holder_name: "ジンジベル").account_number
    @orca.grant_account(@mine)
    @zingiber.grant_account(@theirs)
    @bank.deposit(@mine, 500)
  end

  def stream(customer) = Turbo::StreamsChannel.send(:stream_name_from, [ customer, :commentary ])
  def event_store = Rails.configuration.event_store
  def last(type) = event_store.read.of_type(type).last
  def said(customer) = broadcasts(stream(customer)).map { ActiveSupport::JSON.decode(it) }.join

  test "出来事ごとに積まれる（実況の係は出来事を購読しているだけ）" do
    assert_enqueued_with(job: MyEvents::CommentaryJob) { @bank.deposit(@theirs, 10) }
  end

  test "自分の口座の入金は本人にだけ。他人の口座の入金は、だれにも流れない" do
    assert_broadcasts(stream(@orca), 1) { MyEvents::CommentaryJob.perform_now(last(Banking::Events::MoneyDeposited)) }
    assert_no_broadcasts(stream(@zingiber)) { MyEvents::CommentaryJob.perform_now(last(Banking::Events::MoneyDeposited)) }
    assert_includes said(@orca), "あなたの口座に 500 ちゅ〜る 入金にゃ！"
    assert_includes said(@orca), %(target="#{MyEvents::CommentaryJob::TARGET}")

    @bank.deposit(@theirs, 777)
    assert_no_broadcasts(stream(@orca)) { MyEvents::CommentaryJob.perform_now(last(Banking::Events::MoneyDeposited)) }
  end

  test "振込: 引き落としは振込元に、入金は振込先に。相手の名前は「ほかのお客さま」" do
    perform_enqueued_jobs(only: ->(job) { job.class.name.start_with?("Transfers::") }) do
      Banking::Bank.new(actor: @orca.actor).transfer(@mine, @theirs, 50)
    end
    [ Banking::Events::TransferRequested, Banking::Events::TransferDebited, Banking::Events::TransferCredited,
      Banking::Events::TransferCompleted ].each { MyEvents::CommentaryJob.perform_now(last(it)) }

    orca, zingiber = said(@orca), said(@zingiber)
    assert_includes orca, "いまあなたからほかのお客さまへ 50 ちゅ〜る！"
    assert_includes orca, "あなたの口座から、振込の 50 ちゅ〜る を引き落としたにゃ"
    assert_not_includes orca, "とどいたにゃ" # 振込先への入金（相手の口座の出来事）は振込元に流れない
    assert_includes zingiber, "ほかのお客さまからあなたへ、50 ちゅ〜る とどいたにゃ！"
    assert_not_includes zingiber, "引き落とした" # 振込元の引き落としは振込先に流れない
    assert_not_includes orca, "ジンジベル"
    assert_not_includes zingiber, "オルカ"
  end

  test "二人承認（行員の内部の手続き）は、口座の持ち主にも流れない。取り消しそのものは流れるが、行員の名前は出さない" do
    desk = ->(staff) { "Approvals::Desk".constantize.new(actor: staff.actor) }
    mistake = last(Banking::Events::MoneyDeposited)
    submitted = desk.(@tama).request_reversal(@mine, mistake.event_id, reason: "金額まちがい")
    desk.(@kuro).approve(submitted.approval_id)

    %w[ApprovalRequested ApprovalGranted ApprovalExecuted].each do |type|
      event = event_store.read.of_type("Approvals::Events::#{type}".constantize).last
      assert_no_broadcasts(stream(@orca)) { MyEvents::CommentaryJob.perform_now(event) }
    end
    assert_broadcasts(stream(@orca), 1) { MyEvents::CommentaryJob.perform_now(last(Banking::Events::DepositReversed)) }
    assert_not_includes said(@orca), "たま"
    assert_not_includes said(@orca), "くろ"
  end
end
