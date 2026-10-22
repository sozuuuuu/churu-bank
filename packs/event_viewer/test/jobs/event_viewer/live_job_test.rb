require "test_helper"

# 生中継: どの出来事でもコミットされたら LiveJob が積まれ、一覧の頭に1行足す Turbo Stream を配信する
class EventViewer::LiveJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  test "出来事ごとに積まれ、日本語の1行を prepend で配信する" do
    bank = Banking::Bank.new(actor: "test")
    assert_enqueued_with(job: EventViewer::LiveJob) { bank.open_account(holder_name: "オルカ") }

    event = Rails.configuration.event_store.read.last
    assert_broadcasts(EventViewer::LiveJob::STREAM, 1) { EventViewer::LiveJob.perform_now(event) }

    message = ActiveSupport::JSON.decode(broadcasts(EventViewer::LiveJob::STREAM).last)
    assert_includes message, %(action="prepend")
    assert_includes message, %(target="#{EventViewer::LiveJob::TARGET}")
    assert_includes message, "口座の開設"
    assert_includes message, "（オルカ）"
  end
end
