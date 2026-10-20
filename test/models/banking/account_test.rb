require "test_helper"

# 集約の単体テスト。イベントストアには触らず、apply されたイベントだけを見る
class Banking::AccountTest < ActiveSupport::TestCase
  def opened_account(balance: 0)
    Banking::Account.new("0000001").tap do |account|
      account.open(holder_name: "オルカ")
      account.deposit(balance) if balance.positive?
    end
  end

  test "開設すると AccountOpened が出る" do
    account = Banking::Account.new("0000001")
    account.open(holder_name: "オルカ")

    assert_equal [ Banking::Events::AccountOpened ], account.unpublished_events.map(&:class)
    assert_equal :active, account.status
  end

  test "同じ口座は二度開設できない" do
    assert_raises(Banking::AlreadyOpened) { opened_account.open(holder_name: "ニル") }
  end

  test "入出金で残高が動く" do
    account = opened_account(balance: 100)
    account.withdraw(30)

    assert_equal 70, account.balance
  end

  test "残高を超える出金はできない" do
    account = opened_account(balance: 100)

    error = assert_raises(Banking::InsufficientFunds) { account.withdraw(101) }
    assert_match "残高不足", error.message
    assert_equal 100, account.balance
  end

  test "金額は正の整数だけ" do
    account = opened_account
    [ 0, -1, 1.5, "10" ].each do |amount|
      assert_raises(ArgumentError) { account.deposit(amount) }
    end
  end

  test "起算日は valid_at（その日の 0 時）として入る" do
    account = opened_account
    account.deposit(10, value_date: Date.new(2026, 10, 1))

    event = account.unpublished_events.to_a.last
    assert_equal Time.zone.local(2026, 10, 1), event.metadata[:valid_at]
  end

  test "凍結中・解約後は入出金できない" do
    account = opened_account
    account.freeze!(reason: "テスト")
    assert_raises(Banking::InvalidState) { account.deposit(10) }

    account.unfreeze!
    account.close!
    assert_raises(Banking::InvalidState) { account.deposit(10) }
  end

  test "残高が残っていると解約できない" do
    assert_raises(Banking::InvalidState) { opened_account(balance: 1).close! }
  end
end
