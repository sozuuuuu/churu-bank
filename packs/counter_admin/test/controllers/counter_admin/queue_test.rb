require "test_helper"

# 行員の窓口の列とチャット（/admin/counter/queue）: 次の方 → チャット → 終わる
class CounterAdmin::QueueTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    @tama = create_staff(name: "たま")
    @kuro = create_staff(name: "くろ")
    @ginger = create_customer(name: "ジンジベル")
    @mike = create_customer(name: "ミケ")
  end

  test "行員のログインがなければ行員のログイン画面へ。利用者のログインでは入れない" do
    get counter_admin_queue_path
    assert_redirected_to new_staff_session_path

    sign_in_as_customer @mike
    get counter_admin_queue_path
    assert_redirected_to new_staff_session_path
  end

  test "列に待っている人が並び、列のチャンネルを購読している" do
    Counter::Desk.take(@ginger)
    Counter::Desk.take(@mike)
    sign_in_as_staff @tama

    get counter_admin_queue_path

    assert_response :success
    assert_select "[data-controller='counter--queue']"
    assert_select ".queue-list li", text: /1 番\s+ジンジベル/
    assert_select ".queue-list li", text: /2 番\s+ミケ/
  end

  test "次の方で順に呼び、そのチャットへ。終わると列へ戻り、次の方を呼べる" do
    Counter::Desk.take(@ginger)
    Counter::Desk.take(@mike)
    sign_in_as_staff @tama

    post counter_admin_call_path
    ginger = CounterTicket.find_by!(customer: @ginger)
    assert_redirected_to counter_admin_ticket_path(ginger)
    follow_redirect!
    assert_select "[data-controller='counter--chat'][data-counter--chat-role-value='staff']"
    assert_select "button", text: "出金依頼の画面を案内する"

    post counter_admin_call_path # 話している途中は呼べない
    assert_equal "waiting", CounterTicket.find_by!(customer: @mike).status

    post counter_admin_ticket_finish_path(ginger)
    assert_redirected_to counter_admin_queue_path
    assert_equal "finished", ginger.reload.status

    post counter_admin_call_path
    assert_equal "called", CounterTicket.find_by!(customer: @mike).status
  end

  test "チャットの横に、その利用者の受付中の出金依頼が出る" do
    bank = Banking::Bank.new(actor: "test")
    number = bank.open_account(holder_name: "ジンジベル").account_number
    bank.deposit(number, 100)
    @ginger.grant_account(number)
    Banking::Bank.new(actor: @ginger.actor).request_withdrawal(number, 30, memo: "おやつ代")
    Counter::Desk.take(@ginger)
    ticket = Counter::Desk.call_next(@tama)
    sign_in_as_staff @tama

    get counter_admin_ticket_path(ticket)

    assert_select "aside", text: /30.*おやつ代/m
    assert_select "a[href^='#{admin_withdrawal_requests_path}']", text: "窓口（出金依頼）で処理する"
  end

  test "呼んでいない行員は見るだけ（発言の欄はない）" do
    Counter::Desk.take(@ginger)
    ticket = Counter::Desk.call_next(@tama)
    sign_in_as_staff @kuro

    get counter_admin_ticket_path(ticket)

    assert_select "textarea", count: 0
    assert_match "呼んだ行員（たま）だけが発言できます", response.body
  end
end
