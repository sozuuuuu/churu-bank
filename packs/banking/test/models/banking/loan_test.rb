require "test_helper"

# ちゅ〜るローン: 借りると口座に入り、手数料（10%）を足した額を返す。全部返すと完済
class Banking::LoanTest < ActiveSupport::TestCase
  setup do
    @bank = Banking::Bank.new(actor: "test")
    @number = @bank.open_account(holder_name: "あずき").account_number
  end

  def event_store = Rails.configuration.event_store
  def balance = Account.find_by!(number: @number).balance

  test "借りると口座に入り、返す額は手数料をふくむ。通帳には「借入」の行" do
    outcome = @bank.lend(@number, 100, memo: "生活費")

    assert_equal 100, balance
    loan = Loan.find_by!(loan_id: outcome.loan_id)
    assert_equal [ 100, 10, 110, "open" ], [ loan.principal, loan.fee, loan.outstanding, loan.status ]
    entry = LedgerEntry.where(account_number: @number).last
    assert_equal [ "loan", 100, "生活費" ], [ entry.kind, entry.amount, entry.memo ]
    # お金の動き（口座）は貸付のストリームにもリンクしている
    types = event_store.read.stream("Loan$#{outcome.loan_id}").map(&:event_type)
    assert_equal %w[Banking::Events::LoanGranted Banking::Events::LoanDisbursed], types
  end

  test "少しずつ返し、全部返すと完済。返す額より多くは返せない" do
    loan_id = @bank.lend(@number, 100).loan_id
    @bank.deposit(@number, 50)

    @bank.repay_loan(loan_id, 60)
    assert_equal [ 50, "open" ], Loan.find_by!(loan_id:).then { [ it.outstanding, it.status ] }
    assert_raises(ArgumentError) { @bank.repay_loan(loan_id, 51) }

    @bank.repay_loan(loan_id, 50)
    loan = Loan.find_by!(loan_id:)
    assert_equal [ 0, "settled" ], [ loan.outstanding, loan.status ]
    assert_equal 40, balance
    assert_raises(Banking::InvalidState) { @bank.repay_loan(loan_id, 1) }
    assert_equal "返済（ちゅ〜るローン）", LedgerEntry.where(account_number: @number).last.kind_label
  end

  test "残高が足りなければ返せない（何も書かない）" do
    loan_id = @bank.lend(@number, 100).loan_id
    @bank.repay_loan(loan_id, 100)

    assert_raises(Banking::InsufficientFunds) { @bank.repay_loan(loan_id, 10) }
    assert_equal 10, Loan.find_by!(loan_id:).outstanding
  end

  test "1回の額と、返す額の合計には上限がある。ほかの口座の貸付は返せない" do
    assert_raises(ArgumentError) { @bank.lend(@number, Banking::Bank::LOAN_MAX + 1) }
    @bank.lend(@number, 300) # 返す額 330
    @bank.lend(@number, 200) # 返す額 220 → 合計 550
    error = assert_raises(Banking::InvalidState) { @bank.lend(@number, 50) } # 55 足すと 605
    assert_includes error.message, "600"

    other = @bank.open_account(holder_name: "こむぎ").account_number
    loan_id = Loan.where(account_number: @number).first.loan_id
    assert_raises(Banking::NotFound) { @bank.repay_loan(loan_id, 10, from: other) }
  end

  test "ドライランでは書かない。読み取りモデルは作り直せる" do
    @bank.lend(@number, 100, dry_run: true)
    assert_equal 0, Loan.count

    loan_id = @bank.lend(@number, 100).loan_id
    @bank.repay_loan(loan_id, 30)
    Projections::Rebuild.new.call
    assert_equal [ 80, "open" ], Loan.find_by!(loan_id:).then { [ it.outstanding, it.status ] }
    assert_equal 70, balance
  end
end
