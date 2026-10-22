require "test_helper"

# 利用者の「わたしの出来事」: 自分の口座にかかわる出来事だけ。他人の口座の出来事・二人承認（行員の内部の手続き）は見せない
class MyEvents::EventsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @tama = create_staff(name: "窓口のたま")
    @kuro = create_staff(name: "係長のくろ")
    @orca = create_customer(name: "オルカ")
    @zingiber = create_customer(name: "ジンジベル")
    staff = Banking::Bank.new(actor: @tama.actor)
    @mine = staff.open_account(holder_name: "オルカ").account_number
    @theirs = staff.open_account(holder_name: "ジンジベル").account_number
    @orca.grant_account(@mine)
    @zingiber.grant_account(@theirs)

    staff.deposit(@mine, 300, memo: "オルカのおこづかい")
    staff.deposit(@theirs, 200, memo: "ジンジベルのおこづかい")
    perform_enqueued_jobs { @transfer_id = Banking::Bank.new(actor: @orca.actor).transfer(@mine, @theirs, 50, memo: "おやつ代").transfer_id }

    # まちがえた入金を二人承認で取り消す（申請・承認は行員の内部の手続き）。packs/customer は二人承認（packs/approvals）に
    # 依存しないので、テストの下ごしらえだけ名前で引く
    desk = ->(staff) { "Approvals::Desk".constantize.new(actor: staff.actor) }
    mistake = staff.deposit(@mine, 100, memo: "まちがい").events.last
    submitted = desk.(@tama).request_reversal(@mine, mistake.event_id, reason: "金額まちがい")
    desk.(@kuro).approve(submitted.approval_id)
  end

  def event_store = Rails.configuration.event_store
  def last_of(type, account: nil)
    events = event_store.read.of_type(type).to_a
    events = events.select { it.data[:account_number] == account } if account
    events.last
  end

  test "利用者のログインがなければ入れない。行員のログインでも入れない（利用者のログイン画面へ）" do
    get events_path
    assert_redirected_to new_customer_session_path

    sign_in_as_staff @tama
    [ events_path, event_path(last_of(Banking::Events::MoneyDeposited).event_id), event_time_machine_path ].each do |path|
      get path
      assert_redirected_to new_customer_session_path
    end
  end

  test "一覧: 自分の口座にかかわる出来事だけを日本語で。生中継は自分の分だけ購読する" do
    sign_in_as_customer @orca
    get events_path

    assert_response :success
    assert_select ".ev-row-label", text: "振込の引き落とし"
    assert_select ".ev-row-label", text: "振込の受付"
    assert_select ".ev-row-label", text: "振込の完了"
    assert_select ".ev-row-label", text: "入金の取消"
    assert_select ".ev-row-summary", text: /オルカのおこづかい/
    assert_no_match "ジンジベルのおこづかい", response.body, "他人の口座の入金は出さない"
    assert_select ".ev-row-label", text: "振込の入金", count: 0 # 振込先（他人の口座）への入金
    assert_select ".ev-row-label", text: "承認の申請", count: 0 # 二人承認は行員の内部の手続き
    assert_select ".ev-row-label", text: "承認", count: 0
    assert_select ".ev-row-actor", text: "オルカ（利用者）"
    assert_select ".ev-row-actor", text: "銀行の行員" # 行員の名前は出さない
    assert_no_match "窓口のたま", response.body
    assert_select "turbo-cable-stream-source[channel=CustomerStreamsChannel][signed-stream-name=?]",
                  CustomerStreamsChannel.signed_stream_name([ @orca, :events ])
    assert_select "##{MyEvents::EventsLiveJob::TARGET}"
    assert_select "#serif[data-controller=serif]" # ねこのセリフ窓
    assert_match "足していくだけ", response.body
  end

  test "他人の口座・他人の出来事・行員だけの出来事は 404" do
    sign_in_as_customer @orca

    get events_path(account: @theirs)
    assert_response :not_found
    get event_time_machine_path(account: @theirs)
    assert_response :not_found
    get event_path(last_of(Banking::Events::MoneyDeposited, account: @theirs).event_id)
    assert_response :not_found
    get event_path(last_of(Banking::Events::TransferCredited).event_id) # 振込先（ジンジベル）の口座への入金
    assert_response :not_found
    get event_path(last_of("Approvals::Events::ApprovalRequested".constantize).event_id)
    assert_response :not_found
    get event_path(SecureRandom.uuid)
    assert_response :not_found

    get events_path(account: @mine)
    assert_response :success
  end

  test "1件の中身とつながりの図: 他人の口座の出来事は図にも出さない" do
    sign_in_as_customer @orca
    get event_path(last_of(Banking::Events::TransferDebited).event_id)

    assert_response :success
    assert_select "h1", "振込の引き落とし"
    assert_select ".ev-fields td", text: "50 ちゅ〜る"
    assert_select "svg.ev-tree .ev-node-label", count: 3
    assert_select "svg.ev-tree .ev-node-label", text: "振込の入金", count: 0
    assert_select "svg.ev-tree .ev-node-label", text: "振込の完了"
    assert_select "[data-controller='event-lens--playback']"
  end

  test "二人承認で実行された取消も見られるが、申請者・承認者などの内部の情報は出さない" do
    sign_in_as_customer @orca
    get event_path(last_of(Banking::Events::DepositReversed).event_id)

    assert_response :success
    assert_select "h1", "入金の取消"
    assert_select ".ev-fields th", text: "承認した人", count: 0
    assert_select ".ev-fields th", text: "申請した人", count: 0
    assert_select ".ev-fields th", text: "承認の申請", count: 0
    assert_select ".ev-fields td", text: "銀行の行員"
    assert_select "svg.ev-tree .ev-node-label", text: "承認", count: 0
  end

  test "タイムマシン: 自分の口座の出来事を足した残高" do
    sign_in_as_customer @orca
    get event_time_machine_path

    assert_response :success
    assert_select "[data-controller='event-lens--time-machine'] .balance", "250 ちゅ〜る" # 300 − 50 + 100 − 100
    assert_select "tr[data-position]", 5
    assert_match "通帳は、出来事を順番に足していったもの", response.body
  end

  test "利用者のメニューから行ける" do
    sign_in_as_customer @orca
    get accounts_path
    assert_select "a[href='#{events_path}']", text: /わたしの出来事/
  end
end
