require "test_helper"

# タイムマシン: 口座の出来事を順に足し合わせると、どの時点の残高も作り直せる。いまの残高は読み取りモデルと同じになる
class EventLens::TimeMachineTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @bank = Banking::Bank.new(actor: "staff:1")
    @orca = @bank.open_account(holder_name: "オルカ").account_number
    @zingiber = @bank.open_account(holder_name: "ジンジベル").account_number
  end

  test "出来事を1件ずつ足した残高と状態。最後は読み取りモデルの残高と同じ" do
    @bank.deposit(@orca, 300)
    perform_enqueued_jobs { @bank.transfer(@orca, @zingiber, 50) }
    withdraw_at_counter(@orca, 30)
    @bank.freeze_account(@orca, reason: "テスト")

    machine = EventLens::TimeMachine.new(@orca)
    assert_equal [ 0, 300, -50, -30, 0 ], machine.lines.map(&:delta)
    assert_equal [ 0, 300, 250, 220, 220 ], machine.lines.map(&:balance)
    assert_equal %w[利用中 利用中 利用中 利用中 凍結中], machine.lines.map(&:status)
    assert_equal (1..5).to_a, machine.lines.map(&:position)

    assert_equal 0, machine.balance_at(0)
    assert_equal 300, machine.balance_at(2)
    assert_equal Account.find_by!(number: @orca).balance, machine.balance
  end

  test "起算日の順と記帳日の順: あとから過去の日付で記帳した入金は、置かれる場所が変わる" do
    @bank.deposit(@orca, 100)
    @bank.deposit(@orca, 40, value_date: 3.days.ago.to_date) # 記帳は今日、起算は3日前

    as_of = EventLens::TimeMachine.new(@orca, basis: :as_of)
    as_at = EventLens::TimeMachine.new(@orca, basis: :as_at)

    assert_equal [ 40, 0, 100 ], as_of.lines.map(&:delta), "起算日の順だと、3日前の入金は開設より前に来る"
    assert_equal [ 0, 100, 40 ], as_at.lines.map(&:delta), "記帳日の順だと、書いた順"
    assert_equal as_of.balance, as_at.balance, "どちらの順で足しても、いまの残高は同じ"
    assert as_of.backdated?(as_of.lines.first.event)
    assert_not as_of.backdated?(as_of.lines.last.event)
  end

  test "知らない並べ方は起算日の順。口座の出来事がなければ 0" do
    assert_equal :as_of, EventLens::TimeMachine.new(@orca, basis: "nanika").basis
    assert_equal 0, EventLens::TimeMachine.new("9999999").balance
  end
end
