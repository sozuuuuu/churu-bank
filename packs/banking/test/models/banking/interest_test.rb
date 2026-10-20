require "test_helper"

# 日次の利息: 前日の終わりの残高（起算日基準）× 年利 ÷ 365。端数は口座ごとに繰り越す
class Banking::InterestTest < ActiveSupport::TestCase
  RATE = "0.365" # 1日 0.1%

  setup do
    travel_to Time.zone.local(2026, 10, 21, 0, 5)
    @bank = Banking::Bank.new(actor: "test")
    @number = @bank.open_account(holder_name: "オルカ").account_number
  end

  def event_store = Rails.configuration.event_store
  def balance = Account.find_by!(number: @number).balance
  def interest_events = event_store.read.stream("Account$#{@number}").of_type(Banking::Events::InterestPaid).to_a

  test "前日の終わりの残高に利息がつき、端数は次の日へ繰り越す" do
    @bank.deposit(@number, 1500, value_date: Date.new(2026, 10, 19))

    @bank.pay_interest(date: Date.new(2026, 10, 19), annual_rate: RATE) # 1.5 → 1 払って 0.5 繰り越し
    assert_equal 1501, balance
    @bank.pay_interest(date: Date.new(2026, 10, 20), annual_rate: RATE) # 1.501 + 0.5 → 2 払って 0.001 繰り越し
    assert_equal 1503, balance

    assert_equal [ 1, 2 ], interest_events.map { it.data[:amount] }
    assert_equal Rational(1, 1000), @bank.load_account(@number).interest_carry
    entry = LedgerEntry.where(account_number: @number, kind: "interest").last
    assert_equal [ 2, "10/20 分の利息", Date.new(2026, 10, 21) ], [ entry.amount, entry.memo, entry.value_date ]
  end

  test "同じ日の利息は何度動いても1回だけ" do
    @bank.deposit(@number, 1000, value_date: Date.new(2026, 10, 20))

    first = @bank.pay_interest(date: Date.new(2026, 10, 20), annual_rate: RATE)
    second = @bank.pay_interest(date: Date.new(2026, 10, 20), annual_rate: RATE)
    Interest::PayJob.perform_now # 既定は前日（10/20）

    assert_equal 1, first.size
    assert_empty second
    assert_equal 1, interest_events.size
    assert_equal 1001, balance
  end

  test "元になる残高は起算日基準で、利息の起算日は翌日" do
    @bank.deposit(@number, 1000, value_date: Date.new(2026, 10, 19)) # 10/19 付
    @bank.deposit(@number, 5000)                                    # 10/21 付（前日の残高には入らない）

    @bank.pay_interest(date: Date.new(2026, 10, 20), annual_rate: RATE)

    assert_equal 1000, interest_events.last.data[:base_balance]
    assert_equal 1000, Banking::Statement.new(@number, date: Date.new(2026, 10, 20)).balance
    assert_equal 6001, Banking::Statement.new(@number, date: Date.new(2026, 10, 21)).balance
  end

  test "1 に満たない日は払わずに端数だけ記録し、通帳にも時点残高にも載せない" do
    @bank.deposit(@number, 400, value_date: Date.new(2026, 10, 1))

    (Date.new(2026, 10, 1)..Date.new(2026, 10, 3)).each { @bank.pay_interest(date: it, annual_rate: RATE) }

    assert_equal [ 0, 0, 1 ], interest_events.map { it.data[:amount] } # 0.4 → 0.8 → 1.2
    assert_equal [ 400, 1 ], LedgerEntry.where(account_number: @number).pluck(:amount)
    assert_equal 2, Banking::Statement.new(@number, date: Date.new(2026, 10, 21)).lines.size
  end

  test "凍結中でも利息はつく。残高 0 と解約済みの口座にはつかない" do
    frozen = @bank.open_account(holder_name: "こおり").account_number
    @bank.deposit(frozen, 1000, value_date: Date.new(2026, 10, 20))
    @bank.freeze_account(frozen, reason: "調査中")
    closed = @bank.open_account(holder_name: "とじ").account_number
    @bank.close_account(closed)

    outcomes = @bank.pay_interest(date: Date.new(2026, 10, 20), annual_rate: RATE)

    assert_equal [ frozen ], outcomes.map(&:account_number)
    assert_equal 1001, Account.find_by!(number: frozen).balance
  end

  test "ドライランは書き込まない" do
    @bank.deposit(@number, 1000, value_date: Date.new(2026, 10, 20))

    outcome = @bank.pay_interest_to(@number, date: Date.new(2026, 10, 20), annual_rate: RATE, dry_run: true)

    assert_equal [ 1000, 1001 ], [ outcome.balance_before, outcome.balance_after ]
    assert_empty interest_events
    assert_equal 1000, balance
  end

  test "利率は設定から読む" do
    assert_equal Rails.configuration.x.banking.annual_interest_rate, Banking::Bank.annual_interest_rate
  end
end
