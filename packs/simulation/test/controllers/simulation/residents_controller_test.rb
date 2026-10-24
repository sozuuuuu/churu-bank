require "test_helper"
require_relative "../../simulation_test_helper"

# 住民の様子（/admin/town）: 行員だけ。住民ごとのカードと町の様子、起動・停止・速さ（表に書くだけ）
class Simulation::ResidentsControllerTest < ActionDispatch::IntegrationTest
  include SimulationTestHelper

  setup do
    @tama = create_staff(name: "たま")
    @komugi = create_resident("こむぎ")
    @komugi.update!(state: "ぶらぶら", mood: 80, money: 120, last_action: "「ちゅ〜る」を買いたいと頼んだ", restarts: 2,
                    last_error: "ころんだ（Stumbled）")
  end

  test "行員のログインがなければ行員のログイン画面へ。利用者のログインでは入れない" do
    get simulation_residents_path
    assert_redirected_to new_staff_session_path

    sign_in_as_customer @komugi.customer
    get simulation_residents_path
    assert_redirected_to new_staff_session_path
  end

  test "住民ごとの今の状態・最後にしたこと・起こし直した回数を出し、Turbo Stream を購読する" do
    sign_in_as_staff @tama
    get simulation_residents_path

    assert_response :success
    assert_select "turbo-cable-stream-source[channel=StaffStreamsChannel]"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@komugi)}" do
      assert_select ".pet-name", text: /こむぎ/
      assert_select ".pet-name", text: /倹約家/
      assert_select "svg.pixel-pet[aria-label]"
      assert_select "dd", text: /ぶらぶら/
      assert_select "dd", text: /「ちゅ〜る」を買いたいと頼んだ/
      assert_select "dd", text: /2 回/
      assert_select "a[href=?]", event_viewer_events_path(account: @komugi.account_number)
    end
    assert_select "#simulation_status", text: /町を動かす係が止まっています/
    assert_select "a[href=?]", simulation_residents_path, text: "住民の様子" # 管理画面のメニュー
    assert_select "form[action=?] select[name=?]", simulation_control_path, "control[seconds_per_day]"
    assert_select "##{Simulation::Board::DEBTS_TARGET}", text: /だれも借金していません/
    assert_select "##{Simulation::Board::LETTERS_TARGET}"
  end

  test "動かす・止める・速さは、表に書くだけ（町を動かす係が読む）" do
    sign_in_as_staff @tama

    patch simulation_control_path, params: { control: { running: true } }
    assert_redirected_to simulation_residents_path
    assert Simulation::Control.current.running
    assert_match "町を動かす係が止まっています", flash[:notice]

    patch simulation_control_path, params: { control: { seconds_per_day: 12 } }
    assert_equal 12, Simulation::Control.current.seconds_per_day

    patch simulation_control_path, params: { control: { seconds_per_day: 5 } }
    assert_predicate flash[:alert], :present?
    assert_equal 12, Simulation::Control.current.seconds_per_day

    patch simulation_control_path, params: { control: { running: false } }
    assert_not Simulation::Control.current.running
  end
end
