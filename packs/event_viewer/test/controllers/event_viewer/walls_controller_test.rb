require "test_helper"

class EventViewer::WallsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @staff = create_staff(name: "窓口のたま")
    @orca = create_customer(name: "オルカ")
    staff_bank = Banking::Bank.new(actor: @staff.actor)
    @from = staff_bank.open_account(holder_name: "オルカ").account_number
    @to = staff_bank.open_account(holder_name: "ジンジベル").account_number
    staff_bank.deposit(@from, 500, memo: "おこづかい")
    perform_enqueued_jobs { @transfer_id = Banking::Bank.new(actor: @orca.actor).transfer(@from, @to, 50).transfer_id }
  end

  def debited = Rails.configuration.event_store.read.of_type(Banking::Events::TransferDebited).last

  test "行員だけ。利用者のログインでは入れない" do
    get event_viewer_wall_path
    assert_redirected_to new_staff_session_path

    sign_in_as_customer @orca
    get event_viewer_wall_path
    assert_redirected_to new_staff_session_path
  end

  test "流れごと: 人（黄）・命令（青）・係（紫）・出来事（オレンジ）のふせん。出来事から中身へ、流れからつながりの図とレーン図へ" do
    sign_in_as_staff @staff
    get event_viewer_wall_path

    assert_response :success
    assert_select ".ev-tabs a.is-current", text: "ふせんの壁"
    assert_select ".sticky-person", text: /オルカ（利用者）/
    assert_select ".sticky-command", text: /振り込む/
    assert_select ".sticky-policy", text: /振込の確定の係/
    assert_select ".wall-arrow-note", text: "「振込の引き落とし」が来たので"
    assert_select "a.sticky-event.kind-money-out[href=?]", event_viewer_event_path(debited.event_id), text: /振込の引き落とし/
    assert_select ".wall-row-links a[href=?]", event_viewer_lanes_path(stream: "Transfer$#{@transfer_id}"), text: "レーン図"
    assert_select ".wall-row-links a[href=?]", event_viewer_wall_path(correlation: debited.correlation_id), text: "この流れだけ"

    get event_viewer_wall_path(correlation: debited.correlation_id)
    assert_select ".wall-row .sticky-hotspot", count: 0, message: "入金まで終わった振込に抜けはない"
  end

  test "流れの抜け: 保留中の振込にはピンクのふせん" do
    perform_enqueued_jobs { Banking::Bank.new(actor: @orca.actor).transfer(@from, @to, Banking::Bank.hold_threshold) }
    sign_in_as_staff @staff
    get event_viewer_wall_path

    assert_select ".wall-row.is-waiting .sticky-hotspot", text: /保留中: 行員が確かめて「通す」のを待っています/
  end

  test "絞り込み: ひとつながりだけ・種類（合わない出来事は薄く）・期間" do
    sign_in_as_staff @staff

    get event_viewer_wall_path(correlation: debited.correlation_id)
    assert_select ".wall-chip", text: /ひとつながりの流れ/
    assert_select ".wall-row", count: 1
    assert_select ".sticky-event", text: /おこづかい/, count: 0

    get event_viewer_wall_path(kind: "money_in", correlation: debited.correlation_id)
    assert_select "a.sticky-event:not(.is-dim)", text: /振込の入金/
    assert_select "a.sticky-event.is-dim", text: /振込の引き落とし/

    get event_viewer_wall_path(from: Date.tomorrow.iso8601)
    assert_select ".wall-row", count: 0
    assert_select ".empty", text: "この絞り込みでは、流れはありません。"
  end

  test "いつもの流れ: 同じ並びをまとめて回数を出す。人は「利用者」「行員」まで" do
    travel 2.seconds
    perform_enqueued_jobs { Banking::Bank.new(actor: @orca.actor).transfer(@from, @to, 20) }
    sign_in_as_staff @staff
    get event_viewer_wall_path(view: "patterns")

    assert_response :success
    assert_select ".wall-views a.is-current", text: "いつもの流れ"
    pattern = css_select(".wall-row").find { it.at_css(".sticky-command")&.text&.include?("振り込む") }
    assert_match(/\d+ 回/, pattern.at_css(".wall-count").text)
    assert_operator pattern.at_css(".wall-count").text.to_i, :>=, 2
    assert_equal "利用者", pattern.at_css(".sticky-person strong").text.strip
    assert_nil pattern.at_css(".sticky-event small"), "いつもの流れでは中身（金額など）を出さない"
  end

  test "ほかの画面から壁へ: 出来事の中身・一覧・レーン図" do
    sign_in_as_staff @staff

    get event_viewer_event_path(debited.event_id)
    assert_select "a[href=?]", event_viewer_wall_path(correlation: debited.correlation_id), text: "ふせんの壁で見る"

    get event_viewer_lanes_path(stream: "Transfer$#{@transfer_id}")
    assert_select "a", text: "ふせんの壁で見る"

    get event_viewer_events_path
    assert_select ".ev-head a[href=?]", event_viewer_wall_path, text: "ふせんの壁"
  end
end
