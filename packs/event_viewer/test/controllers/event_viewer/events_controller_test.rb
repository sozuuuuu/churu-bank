require "test_helper"

class EventViewer::EventsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @staff = create_staff(name: "窓口のたま")
    @orca = create_customer(name: "オルカ")
    bank = Banking::Bank.new(actor: @orca.actor)
    staff_bank = Banking::Bank.new(actor: @staff.actor)
    @from = staff_bank.open_account(holder_name: "オルカ").account_number
    @to = staff_bank.open_account(holder_name: "ジンジベル").account_number
    staff_bank.deposit(@from, 120, memo: "おこづかい")
    perform_enqueued_jobs { @transfer_id = bank.transfer(@from, @to, 50).transfer_id }
  end

  def event_store = Rails.configuration.event_store
  def debited = event_store.read.of_type(Banking::Events::TransferDebited).last

  test "利用者のログインでは入れない（行員のログイン画面へ）。ログインしていなくても同じ" do
    paths = [ event_viewer_events_path, event_viewer_event_path(debited.event_id), event_viewer_time_machine_path, event_viewer_lanes_path ]
    paths.each do |path|
      get path
      assert_redirected_to new_staff_session_path
    end

    sign_in_as_customer @orca
    paths.each do |path|
      get path
      assert_redirected_to new_staff_session_path
    end
  end

  test "一覧: イベント名・ストリーム・金額・だれが、を日本語で。生中継を購読する" do
    sign_in_as_staff @staff
    get event_viewer_events_path

    assert_response :success
    assert_select ".ev-row-label", text: "振込の引き落とし"
    assert_select ".ev-row-label", text: "入金"
    assert_select ".ev-row-where", text: "口座 #{@from}（オルカ）"
    assert_select ".ev-row-summary", text: /120 ちゅ〜る/
    assert_select ".ev-row-actor", text: "オルカ（利用者）"
    assert_select ".ev-row-actor", text: "窓口のたま（行員）"
    assert_select "turbo-cable-stream-source[channel=StaffStreamsChannel]"
    assert_select "##{EventViewer::LiveJob::TARGET}"
  end

  test "絞り込み: 種類・口座・日付。絞り込み中は生中継しない" do
    sign_in_as_staff @staff

    get event_viewer_events_path(kind: "money_in")
    assert_select ".ev-row-label", text: "入金"
    assert_select ".ev-row-label", text: "振込の入金"
    assert_select ".ev-row-label", text: "振込の引き落とし", count: 0
    assert_select "turbo-cable-stream-source", count: 0

    get event_viewer_events_path(account: @to)
    assert_select ".ev-row-label", text: "振込の入金"
    assert_select ".ev-row-label", text: "入金", count: 0

    get event_viewer_events_path(date: 1.day.ago.to_date.iso8601)
    assert_select ".ev-row", count: 0
  end

  test "1件の中身: 項目名と値を日本語で、つながりの図を描く" do
    sign_in_as_staff @staff
    get event_viewer_event_path(debited.event_id)

    assert_response :success
    assert_select "h1", "振込の引き落とし"
    assert_select ".ev-fields th", text: "金額"
    assert_select ".ev-fields td", text: "50 ちゅ〜る"
    assert_select ".ev-fields td", text: "#{@to}（ジンジベル）"
    assert_select ".ev-fields td", text: "オルカ（利用者）"
    assert_select ".ev-streams li", text: /振込 ##{@transfer_id.first(4)}/
    assert_select "svg.ev-tree .ev-node", 4
    assert_select "svg.ev-tree .ev-node.is-seed .ev-node-label", "振込の引き落とし"
    assert_select "svg.ev-tree path.ev-edge-cause", 1
    assert_select "[data-controller='event-viewer--playback']"
  end

  test "ない出来事は 404" do
    sign_in_as_staff @staff
    get event_viewer_event_path(SecureRandom.uuid)
    assert_response :not_found
  end

  test "タイムマシン: 口座の出来事を足した残高と通帳。並べ方を選べる" do
    sign_in_as_staff @staff
    get event_viewer_time_machine_path(account: @from, basis: "as_at")

    assert_response :success
    assert_select "[data-controller='event-viewer--time-machine'] .balance", "70 ちゅ〜る"
    assert_select "tr[data-position]", 3
    assert_select "tr[data-position='2'][data-balance='120']"
    assert_select "input[type=range][max='3']"
    assert_select "input[type=radio][value=as_at][checked]"
  end

  test "レーン図: 振込を選ぶと関係者のレーン" do
    sign_in_as_staff @staff
    get event_viewer_lanes_path(stream: "Transfer$#{@transfer_id}")

    assert_response :success
    assert_select "svg.ev-lanes .ev-lane", 3
    assert_select "svg.ev-lanes .ev-lane-name", text: "オルカ"
    assert_select "svg.ev-lanes .ev-dot", 4

    get event_viewer_lanes_path(stream: "Account$#{@from}") # 業務のストリームでなければ図は出さない
    assert_response :success
    assert_select "svg.ev-lanes", count: 0
  end

  test "管理画面のメニューの「イベント」はこの画面へ。英語の RES Browser は「詳しく見る（英語）」" do
    sign_in_as_staff @staff
    get admin_accounts_path
    assert_select "a[href='#{event_viewer_events_path}']", text: "イベント"

    get event_viewer_events_path
    assert_select "a[href='/res']", text: "詳しく見る（英語）"
  end
end
