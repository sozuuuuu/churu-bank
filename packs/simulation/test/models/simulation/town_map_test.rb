require "test_helper"

# 住民の様子（RPG の画面）の地図: いましていること → どの建物の前にいるか
class Simulation::TownMapTest < ActiveSupport::TestCase
  M = Simulation::TownMap

  def resident(state, last_action = nil) = Simulation::ResidentStatus.new(name: "こむぎ", state:, last_action:)

  test "いましていること（state）から行き先を決める。最後にしたことは見ない。どれでもなければ広場" do
    assert_equal :work, M.destination(resident("しごと場で働いている"))
    assert_equal :matatabi_bar, M.destination(resident("またたびバーにいる"))
    assert_equal :bank, M.destination(resident("銀行の窓口にいる"))
    assert_equal :home, M.destination(resident("ねている"))
    assert_equal :shop, M.destination(resident("ごはんを買いに行った"))
    assert_equal :landlord, M.destination(resident("大家さんの家にいる"))
    assert_equal :plaza, M.destination(resident("ぶらぶら", "窓口: お給料 170 ちゅ〜るを振り込みました")), "朝のお給料のあと"
    assert_equal :plaza, M.destination(resident("夕方のひととき", "みんなに「30 ちゅ〜る足りないにゃ」と手紙を出した"))
  end

  test "立つマスは地図の中。同じ建物の前でも、名簿の順で少しずれる" do
    spots = (0..4).map { M.spot(resident("ちゅ〜る商店にいる"), it) }
    assert_equal 5, spots.map(&:first).uniq.size
    assert spots.all? { |x, y| x.between?(0, M::COLS) && y.between?(0, M::ROWS) }
    assert_equal "ちゅ〜る商店", M.place_name(resident("ちゅ〜る商店にいる"))
    assert_equal "こむぎの家", M.place_name(resident("ねている"))
  end

  test "地図のタイルは1マスに1つで、噴水は広場の真ん中" do
    tiles = M.tiles
    assert_equal tiles.size, tiles.map { it[0, 2] }.uniq.size
    assert_includes tiles, [ *M::PLAZA, :water ]
  end
end
