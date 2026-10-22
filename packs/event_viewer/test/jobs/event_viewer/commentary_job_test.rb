require "test_helper"

# 行員のねこの実況: どの出来事でも積まれ、名前と金額の入った実況の1行を prepend で配信する
class EventViewer::CommentaryJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  test "出来事ごとに積まれ、実況の1行を配信する" do
    bank = Banking::Bank.new(actor: "test")
    orca = bank.open_account(holder_name: "オルカ").account_number
    assert_enqueued_with(job: EventViewer::CommentaryJob) { bank.deposit(orca, 300) }

    event = Rails.configuration.event_store.read.last
    assert_broadcasts(EventViewer::CommentaryJob::STREAM, 1) { EventViewer::CommentaryJob.perform_now(event) }

    message = ActiveSupport::JSON.decode(broadcasts(EventViewer::CommentaryJob::STREAM).last)
    assert_includes message, %(action="prepend")
    assert_includes message, %(target="#{EventViewer::CommentaryJob::TARGET}")
    assert_includes message, "オルカさんの口座に 300 ちゅ〜る 入金にゃ！"
    assert_includes message, %(data-face="happy")
  end
end
