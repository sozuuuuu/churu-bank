require "test_helper"

# イベントストア → プロジェクション → 時点指定の残高まで、通しで確かめる
class Banking::BankTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @bank = Banking::Bank.new(actor: "test")
    @number = @bank.open_account(holder_name: "オルカ").account_number
  end

  def event_store = Rails.configuration.event_store

  test "書き込むとイベントと読み取りモデルの両方が更新される" do
    @bank.deposit(@number, 100, memo: "おこづかい")
    withdraw_at_counter(@number, 30)

    account = Account.find_by!(number: @number)
    assert_equal 70, account.balance
    assert_equal [ 100, -30 ], account.ledger_entries.pluck(:amount)
    assert_equal [ 100, 70 ], account.ledger_entries.pluck(:balance_after)
    assert_equal 3, event_store.read.stream("Account$#{@number}").count
  end

  test "誰が操作したかが metadata に残る" do
    @bank.deposit(@number, 1)

    event = event_store.read.stream("Account$#{@number}").last
    assert_equal "test", event.metadata[:actor]
    assert_equal "test", LedgerEntry.last.actor
  end

  test "ドライランは何も書き込まずに結果だけ返す" do
    @bank.deposit(@number, 100)

    outcome = @bank.deposit(@number, 40, dry_run: true)

    assert outcome.dry_run?
    assert_equal [ 100, 140 ], [ outcome.balance_before, outcome.balance_after ]
    assert_equal 100, Account.find_by!(number: @number).balance
    assert_equal 2, event_store.read.stream("Account$#{@number}").count
  end

  test "失敗したときは何も残らない" do
    assert_raises(Banking::InsufficientFunds) { withdraw_at_counter(@number, 1) }

    assert_equal 1, event_store.read.stream("Account$#{@number}").count
    assert_empty LedgerEntry.where(account_number: @number)
  end

  test "同時に更新されたら後から来た方が失敗する" do
    @bank.deposit(@number, 100)
    stale = @bank.load_account(@number) # この時点の version で止めておく
    withdraw_at_counter(@number, 100) # 先に別の誰かが全額出金

    stale.withdraw(100) # 古い残高（100）では通ってしまうが…
    assert_raises(RubyEventStore::WrongExpectedEventVersion) do
      AggregateRoot::Repository.new(event_store).store(stale, "Account$#{@number}")
    end
    assert_equal 0, Account.find_by!(number: @number).balance
  end

  test "起算日基準と記帳日基準で、時点の残高が変わる" do
    travel_to Time.zone.local(2026, 10, 20, 12) do
      @bank.deposit(@number, 100)                                      # 10/20 に記帳
      @bank.deposit(@number, 50, value_date: Date.new(2026, 10, 17))   # 10/20 に、10/17 付で記帳
    end

    on_18th = Date.new(2026, 10, 18)
    assert_equal 50, Banking::Statement.new(@number, date: on_18th, basis: :as_of).balance
    assert_equal 0, Banking::Statement.new(@number, date: on_18th, basis: :as_at).balance
    assert_equal 150, Banking::Statement.new(@number, date: Date.new(2026, 10, 20)).balance
  end
end
