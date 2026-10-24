# ねこ町の試験の道具。Ractor を使う試験は、待つ時間に上限をつけて、長くても数秒で終わるようにする
module SimulationTestHelper
  # port に、ブロックが真になる手紙が届くまで待って、その手紙を返す（ほかの手紙は読み捨てる）。
  # Ractor::Port#receive には待つ時間の上限がないので、糸（Thread）で待って join に上限をつける
  def wait_for(port, seconds: 3, &matcher)
    waiter = Thread.new do
      loop do
        letter = port.receive
        break letter if matcher.call(letter)
      end
    end
    waiter.join(seconds) or flunk "#{seconds} 秒待っても、手紙が届きませんでした"
    waiter.value
  ensure
    waiter&.kill
  end

  # Ractor が終わるのを待つ（上限つき）
  def join_within(ractor, seconds: 3)
    waiter = Thread.new { ractor.join }
    waiter.join(seconds) or flunk "#{seconds} 秒待っても、Ractor が終わりませんでした"
  ensure
    waiter&.kill
  end

  def spec_for(name, temperament: :frugal, friends: [], menu: [], seed: 1)
    Ractor.make_shareable(Simulation::Resident::Spec.new(name:, temperament:, brain: :rules, seed:, friends:, menu:))
  end

  # 住民の利用者・口座・様子の行を作る
  def create_resident(name, deposit: 100, temperament: :frugal)
    customer = create_customer(name:)
    bank = Banking::Bank.new(actor: "test")
    number = bank.open_account(holder_name: name).account_number
    customer.grant_account(number)
    bank.deposit(number, deposit) if deposit.positive?
    Simulation::ResidentStatus.create!(name:, customer:, account_number: number, temperament: temperament.to_s)
  end
end
