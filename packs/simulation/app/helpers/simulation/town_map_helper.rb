# 町の地図（RPG のフィールド）を SVG で描く。1マス = 16。草は模様（pattern）でしきつめ、ほかのタイルと建物を上に重ねる
module Simulation
  module TownMapHelper
    TILE = 16

    def town_map_svg
      width, height = TownMap::COLS * TILE, TownMap::ROWS * TILE
      tag.svg(class: "rpg-map-svg", viewBox: "0 0 #{width} #{height}", "shape-rendering": "crispEdges",
              role: "img", "aria-label": "ねこ町の地図") do
        safe_join([
          map_defs,
          tag.rect(width:, height:, fill: "url(#rpg-grass)"),
          safe_join(TownMap.tiles.map { |x, y, kind| map_tile(x * TILE, y * TILE, kind) }),
          safe_join(TownMap::BUILDINGS.map { map_building(it) }),
          safe_join(ResidentStatus.order(:id).each_with_index.map { |resident, index| map_home(resident, index) })
        ])
      end
    end

    private

    def map_defs
      tag.defs do
        tag.pattern(id: "rpg-grass", width: TILE, height: TILE, patternUnits: "userSpaceOnUse") do
          safe_join([
            tag.rect(width: TILE, height: TILE, fill: "#6abe30"),
            *[ [ 3, 4 ], [ 11, 2 ], [ 7, 11 ], [ 13, 13 ] ].map { |x, y| tag.rect(x:, y:, width: 1, height: 2, fill: "#4b9a22") }
          ])
        end
      end
    end

    def map_tile(x, y, kind)
      case kind
      when :road
        safe_join([ tag.rect(x:, y:, width: TILE, height: TILE, fill: "#d9b77e"),
                    tag.rect(x: x + 3, y: y + 5, width: 2, height: 1, fill: "#b8945c"),
                    tag.rect(x: x + 10, y: y + 11, width: 2, height: 1, fill: "#b8945c") ])
      when :plaza
        safe_join([ tag.rect(x:, y:, width: TILE, height: TILE, fill: "#cfc4ae"),
                    tag.rect(x:, y: y + 7, width: TILE, height: 1, fill: "#b3a78f"),
                    tag.rect(x: x + 7, y:, width: 1, height: TILE, fill: "#b3a78f") ])
      when :water
        safe_join([ tag.rect(x:, y:, width: TILE, height: TILE, fill: "#cfc4ae"),
                    tag.rect(x: x + 1, y: y + 3, width: 14, height: 11, fill: "#8d8d8d"),
                    tag.rect(x: x + 2, y: y + 4, width: 12, height: 9, fill: "#4fa3e0"),
                    tag.rect(x: x + 7, y: y + 1, width: 2, height: 6, fill: "#bfe6ff", class: "rpg-fountain"),
                    tag.rect(x: x + 4, y: y + 8, width: 2, height: 1, fill: "#fff") ])
      when :tree
        safe_join([ tag.rect(x: x + 6, y: y + 11, width: 4, height: 5, fill: "#6d4c41"),
                    tag.rect(x: x + 2, y: y + 2, width: 12, height: 10, fill: "#2e7d32"),
                    tag.rect(x: x + 4, y:, width: 8, height: 2, fill: "#2e7d32"),
                    tag.rect(x: x + 4, y: y + 3, width: 4, height: 3, fill: "#43a047") ])
      when :flower
        safe_join([ [ 3, 4, "#ff8fb1" ], [ 10, 6, "#ffe066" ], [ 6, 11, "#ff8fb1" ], [ 12, 12, "#fff" ] ].map do |dx, dy, color|
          tag.rect(x: x + dx, y: y + dy, width: 2, height: 2, fill: color)
        end)
      end
    end

    # 建物: 屋根・壁・窓・入口・看板
    def map_building(building)
      x, y = building.x * TILE, building.y * TILE
      w, h = building.w * TILE, building.h * TILE
      door_x = building.door[0] * TILE
      tag.g(class: "rpg-building") do
        safe_join([
          tag.rect(x: x + 1, y: y + 12, width: w - 2, height: h - 12, fill: "#f3e2c7", stroke: "#3b2a1a"),
          tag.rect(x: x - 1, y: y + 1, width: w + 2, height: 13, fill: building.roof, stroke: "#3b2a1a"),
          tag.rect(x:, y: y + 11, width: w, height: 2, fill: "rgba(0,0,0,.25)"),
          tag.rect(x: x + 5, y: y + 20, width: 8, height: 7, fill: "#8fd3ff", stroke: "#3b2a1a"),
          tag.rect(x: x + w - 13, y: y + 20, width: 8, height: 7, fill: "#8fd3ff", stroke: "#3b2a1a"),
          tag.rect(x: door_x + 4, y: y + h - 13, width: 8, height: 13, fill: "#6d4c41", stroke: "#3b2a1a"),
          tag.text(building.name, x: x + (w / 2), y: y + 10, class: "rpg-sign", "text-anchor": "middle")
        ])
      end
    end

    def map_home(resident, index)
      hx, hy = TownMap.home(index)
      x, y = hx * TILE, hy * TILE
      tag.g(class: "rpg-home") do
        safe_join([
          tag.rect(x: x + 2, y: y + 12, width: 28, height: 20, fill: "#fff4e0", stroke: "#3b2a1a"),
          tag.rect(x:, y: y + 2, width: 32, height: 11, fill: "#b5651d", stroke: "#3b2a1a"),
          tag.rect(x: x + 13, y: y + 22, width: 6, height: 10, fill: "#6d4c41"),
          tag.text(resident.name, x: x + 16, y: y + 10, class: "rpg-sign", "text-anchor": "middle")
        ])
      end
    end
  end
end
