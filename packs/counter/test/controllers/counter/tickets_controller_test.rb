require "test_helper"

# 利用者の窓口（/counter）: 札を取る → 待つ → 呼ばれてチャット → 返す。見えるのは自分の札だけ
class Counter::TicketsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @mike = create_customer(name: "ミケ")
    @ginger = create_customer(name: "ジンジベル")
    @tama = create_staff(name: "たま")
  end

  test "ログインしていなければ利用者のログイン画面へ。行員のログインでは入れない" do
    get counter_path
    assert_redirected_to new_customer_session_path

    sign_in_as_staff @tama
    get counter_path
    assert_redirected_to new_customer_session_path
  end

  test "札を取ると番号と前の人数が出て、自分の札のチャンネルを購読する" do
    Counter::Desk.take(@ginger)
    sign_in_as_customer @mike

    get counter_path
    assert_select "button", text: /番号札を取る/

    post counter_path
    assert_redirected_to counter_path
    follow_redirect!

    ticket = CounterTicket.find_by!(customer: @mike)
    assert_select ".ticket-number strong", text: "2"
    assert_select ".ticket-ahead", text: /前に 1 人/
    assert_select "[data-controller='counter--ticket'][data-counter--ticket-ticket-id-value='#{ticket.id}']"
    assert_select "#serif[data-serif-text-value*='2 番の札をとったにゃ']"
  end

  test "呼ばれたらチャットになり、ねこがうれしい顔で呼ぶ。出金依頼の画面へのリンクも用意される" do
    @mike.grant_account("0000123")
    Counter::Desk.take(@mike)
    Counter::Desk.call_next(@tama)
    sign_in_as_customer @mike

    get counter_path

    assert_select "[data-controller='counter--chat'][data-counter--chat-role-value='customer']"
    assert_select "#serif[data-serif-face-value='happy'][data-serif-text-value*='1 番の方、窓口へどうぞにゃ']"
    assert_select "template a[href='#{account_path("0000123", anchor: "withdrawal-requests")}']"
  end

  test "札を返せる" do
    Counter::Desk.take(@mike)
    sign_in_as_customer @mike

    delete counter_path

    assert_redirected_to counter_path
    assert_equal "returned", CounterTicket.sole.status
  end

  test "他人の札やチャットは見えない（自分の札だけを出す）" do
    Counter::Desk.take(@ginger)
    Counter::Desk.call_next(@tama)
    Counter::Desk.speak(CounterTicket.sole.id, role: "customer", person: @ginger, body: "ないしょの話")
    sign_in_as_customer @mike

    get counter_path

    assert_select "[data-controller='counter--chat']", count: 0
    assert_no_match "ないしょの話", response.body
  end
end
