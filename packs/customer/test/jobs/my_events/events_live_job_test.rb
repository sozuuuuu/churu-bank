require "test_helper"

# 利用者の生中継: 出来事を見てよい利用者（かかわる口座の持ち主）にだけ配信する
class MyEvents::EventsLiveJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  setup do
    @orca = create_customer(name: "オルカ")
    @zingiber = create_customer(name: "ジンジベル")
    bank = Banking::Bank.new(actor: "staff:1")
    @mine = bank.open_account(holder_name: "オルカ").account_number
    @theirs = bank.open_account(holder_name: "ジンジベル").account_number
    @orca.grant_account(@mine)
    @zingiber.grant_account(@theirs)
    bank.deposit(@mine, 100)
  end

  def stream(customer) = Turbo::StreamsChannel.send(:stream_name_from, [ customer, :events ])
  def event_store = Rails.configuration.event_store

  test "自分の口座の出来事は本人にだけ。振込は、引き落としは振込元に、入金は振込先に" do
    deposit = event_store.read.of_type(Banking::Events::MoneyDeposited).last
    assert_broadcasts(stream(@orca), 1) { MyEvents::EventsLiveJob.perform_now(deposit) }
    assert_no_broadcasts(stream(@zingiber)) { MyEvents::EventsLiveJob.perform_now(deposit) }
    assert_includes ActiveSupport::JSON.decode(broadcasts(stream(@orca)).last), "入金"

    perform_enqueued_jobs(only: ->(job) { job.class.name.start_with?("Transfers::") }) do
      Banking::Bank.new(actor: @orca.actor).transfer(@mine, @theirs, 30)
    end
    debited = event_store.read.of_type(Banking::Events::TransferDebited).last
    credited = event_store.read.of_type(Banking::Events::TransferCredited).last
    completed = event_store.read.of_type(Banking::Events::TransferCompleted).last

    assert_broadcasts(stream(@orca), 1) { MyEvents::EventsLiveJob.perform_now(debited) }
    assert_no_broadcasts(stream(@zingiber)) { MyEvents::EventsLiveJob.perform_now(debited) }
    assert_broadcasts(stream(@zingiber), 1) { MyEvents::EventsLiveJob.perform_now(credited) }
    assert_no_broadcasts(stream(@orca)) { MyEvents::EventsLiveJob.perform_now(credited) }
    # 振込そのもの（Transfer$）の出来事は、振込元と振込先の両方
    assert_broadcasts(stream(@orca), 1) { MyEvents::EventsLiveJob.perform_now(completed) }
    assert_broadcasts(stream(@zingiber), 1) { MyEvents::EventsLiveJob.perform_now(completed) }
  end
end
