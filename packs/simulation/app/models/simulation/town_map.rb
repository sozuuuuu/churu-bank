# 住民の様子（RPG の画面）の町の地図。24×14 マスのタイルに、建物と道と広場を置く。
# 住民が「いましていること」（ResidentStatus の state）から、どの建物の前にいるかを決める（spot）。
# 「最後にしたこと」は見ない（朝にお給料をもらったあと、昼もしごと場にいるように見えてしまうので）。
# 住民の居場所は画面だけのもので、住民の Ractor は地図を知らない
module Simulation
  module TownMap
    COLS = 24
    ROWS = 14

    # 建物: key, 名前（看板）, x, y, 幅, 高さ, 屋根の色
    Building = Data.define(:key, :name, :x, :y, :w, :h, :roof) do
      def door = [ x + (w / 2), y + h - 1 ]

      # 入口の前のマス（住民が立つところ）
      def front = [ door[0], door[1] + 1 ]
    end

    BUILDINGS = [
      Building.new(:work, "しごと場", 1, 1, 4, 3, "#8a6a4a"),
      Building.new(:bank, "銀行", 6, 1, 4, 3, "#3b6fb6"),
      Building.new(:shop, "ちゅ〜る商店", 13, 1, 4, 3, "#d0577f"),
      Building.new(:landlord, "大家さん", 18, 1, 4, 3, "#7a7a7a"),
      Building.new(:matatabi_bar, "またたびバー", 1, 9, 4, 3, "#6b3fa0"),
      Building.new(:cat_cafe, "ねこカフェ", 6, 9, 4, 3, "#e08a3c"),
      Building.new(:onsen, "温泉", 13, 9, 4, 3, "#c0392b"),
      Building.new(:lottery, "宝くじ", 18, 9, 4, 3, "#d4a017")
    ].freeze
    # 住民の家（名簿の順に1軒ずつ。幅2・高さ2）
    HOMES = [ [ 1, 5 ], [ 4, 5 ], [ 7, 5 ], [ 13, 5 ], [ 16, 5 ] ].freeze
    PLAZA = [ 21, 6 ].freeze # 噴水
    STREETS = [ 4, 8, 12 ].freeze # 横の道（y）
    AVENUE = 11 # 縦の道（x）

    # いましていること → 行き先（建物の key か :home / :plaza）
    PLACES_BY_WORD = {
      "しごと場" => :work, "給料" => :work, "銀行" => :bank, "ローン" => :bank, "返し" => :bank,
      "商店" => :shop, "ごはん" => :shop, "家賃" => :landlord, "大家" => :landlord,
      "またたびバー" => :matatabi_bar, "ねこカフェ" => :cat_cafe, "温泉" => :onsen, "宝くじ" => :lottery,
      "ねて" => :home, "ねむった" => :home, "朝のしたく" => :home, "町を出た" => :home, "起きた" => :home
    }.freeze

    module_function

    def building(key) = BUILDINGS.find { it.key == key }

    def home(index) = HOMES[index % HOMES.size]

    # 住民の行き先（key）。いましていること（state）から。どれでもなければ（ぶらぶら・夕方のひととき）広場
    def destination(resident)
      PLACES_BY_WORD.each { |word, key| return key if resident.state.to_s.include?(word) }
      :plaza
    end

    # 住民の立つマス（小数あり）。同じ所に何匹いても重ならないように、名簿の順で少しずらす
    def spot(resident, index)
      key = destination(resident)
      x, y = case key
      when :home then home(index).then { |hx, hy| [ hx + 0.5, hy + 2 ] }
      when :plaza then [ PLAZA[0] - 0.5, PLAZA[1] + 1 ] # 噴水の下に並ぶ（ずらし方はほかの所と同じ）
      else building(key).front
      end
      # 5匹が同じ所にいても名前が読めるように、横に並べて、1匹おきに少し下げる
      [ x + (((index % 5) - 2) * 0.8), y - 0.2 + (index.odd? ? 0.7 : 0) ]
    end

    def place_name(resident)
      key = destination(resident)
      case key
      when :home then "#{resident.name}の家"
      when :plaza then "噴水の広場"
      else building(key).name
      end
    end

    # 地図のタイル: [[x, y, 種類]]。:grass はしきつめるので返さない
    def tiles
      @tiles ||= begin
        tiles = []
        (0...COLS).each { |x| tiles << [ x, 0, :tree ] << [ x, ROWS - 1, :tree ] }
        (1...ROWS - 1).each { |y| tiles << [ 0, y, :tree ] << [ COLS - 1, y, :tree ] }
        STREETS.each { |y| (1...COLS - 1).each { |x| tiles << [ x, y, :road ] } }
        (1...ROWS - 1).each { |y| tiles << [ AVENUE, y, :road ] }
        HOMES.each { |hx, hy| tiles << [ hx + 1, hy + 2, :road ] } # 家の前から道へ
        tiles << [ PLAZA[0], PLAZA[1], :water ] # 同じマスは先に入れたものが残る（uniq）ので、噴水を先に
        (PLAZA[0] - 1..PLAZA[0] + 1).each { |x| (PLAZA[1] - 1..PLAZA[1] + 1).each { |y| tiles << [ x, y, :plaza ] } }
        [ [ 9, 6 ], [ 10, 6 ], [ 12, 6 ], [ 19, 5 ], [ 19, 7 ] ].each { |x, y| tiles << [ x, y, :flower ] }
        tiles.uniq { it[0, 2] }.freeze
      end
    end
  end
end
