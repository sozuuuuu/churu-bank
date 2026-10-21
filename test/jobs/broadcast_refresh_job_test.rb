require "test_helper"
require "turbo/broadcastable/test_helper"

class BroadcastRefreshJobTest < ActiveJob::TestCase
  # assert_turbo_stream_broadcasts。turbo-rails が自動で入れるのは Action Cable のサーバーが読み込まれた後（on_load(:action_cable)）で、
  # ほかのテストが先に配信していないと入っていないことがあるので、ここで入れる
  include Turbo::Broadcastable::TestHelper
  setup do
    @bank = Banking::Bank.new(actor: "test")
    @number = @bank.open_account(holder_name: "オルカ").account_number
  end

  test "口座のイベントがコミットされると積まれる" do
    assert_enqueued_with(job: BroadcastRefreshJob) do
      @bank.deposit(@number, 1)
    end
  end

  test "口座のページと口座一覧に refresh を配信する" do
    @bank.deposit(@number, 1)
    account = Account.find_by!(number: @number)

    assert_turbo_stream_broadcasts(account) do
      assert_turbo_stream_broadcasts("accounts") do
        perform_enqueued_jobs(only: BroadcastRefreshJob)
      end
    end
  end
end
