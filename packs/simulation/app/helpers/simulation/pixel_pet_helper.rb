# 住民のドット絵（たまごっち・デジモンの液晶のつもり）。16×16 のねこを SVG の四角で描き、いまの様子でポーズを変える。
# 液晶は2色（濃い点と薄い点）だけ。動き（ぴょこぴょこ・Zz・ハート…）は CSS の steps() でカクカク動かす（simulation.css）
module Simulation
  module PixelPetHelper
    # ねこの体（目と口は POSES ごとに重ねる）。# 濃い点・+ 薄い点（ほっぺ・足の裏）・. なにもない
    BODY = %w[
      ................
      ..#..........#..
      ..##........##..
      ..#+#......#+#..
      ..#..######..#..
      .#............#.
      .#............#.
      .#............#.
      .#............#.
      .#++........++#.
      .#............#.
      ..#..........#..
      ...##########...
      ...#..#..#..#...
      ...###....###...
      ................
    ].freeze

    # 顔のパーツ: [x, y, 点の並び]（点の並びは BODY と同じ書き方、行は | で区切る）
    EYES = {
      open: [ [ 4, 7, "##|##" ], [ 10, 7, "##|##" ] ],
      closed: [ [ 4, 8, "##" ], [ 10, 8, "##" ] ],
      happy: [ [ 4, 7, ".#.|#.#" ], [ 9, 7, ".#.|#.#" ] ],
      sad: [ [ 4, 7, "#..|.##" ], [ 9, 7, "..#|##." ] ],
      dizzy: [ [ 4, 7, "#.#|.#.|#.#" ], [ 9, 7, "#.#|.#.|#.#" ] ]
    }.freeze
    MOUTHS = {
      smile: [ 6, 10, "#..#|.##." ],
      flat: [ 7, 10, "##" ],
      open: [ 7, 10, "##|##" ],
      frown: [ 6, 10, ".##.|#..#" ]
    }.freeze

    # 横に出すしるし（5×5、x = 16 の右側に描く）
    MARKS = {
      zzz: "###..|..#..|.#...|###..|.....",
      heart: ".#.#.|#####|#####|.###.|..#..",
      food: "..#..|.###.|#####|.###.|..#..",
      note: "..##.|..#.#|..#..|###..|##...",
      sweat: "..#..|.#+#.|#+++#|#+++#|.###.",
      star: "#.#.#|.###.|#####|.###.|#.#.#",
      coin: ".###.|#+#+#|#+#+#|#+#+#|.###."
    }.freeze

    # ポーズ: [目, 口, しるし]
    POSES = {
      normal: [ :open, :flat, nil ],
      happy: [ :happy, :smile, :heart ],
      sad: [ :sad, :frown, nil ],
      sleep: [ :closed, :flat, :zzz ],
      eat: [ :open, :open, :food ],
      play: [ :happy, :smile, :note ],
      worry: [ :open, :frown, :sweat ],
      rich: [ :happy, :smile, :coin ],
      dizzy: [ :dizzy, :open, :star ]
    }.freeze
    POSE_LABELS = {
      normal: "ふつう", happy: "ごきげん", sad: "しょんぼり", sleep: "おやすみ", eat: "もぐもぐ", play: "あそび中",
      worry: "借金でひやひや", rich: "おかねもち", dizzy: "ころんだ！"
    }.freeze
    PLAY_WORDS = %w[またたびバー ねこカフェ 温泉 宝くじ].freeze

    # いまの様子 → ポーズ
    def pet_pose(resident)
      text = "#{resident.state} #{resident.last_action}"
      return :dizzy if resident.face == :surprised
      return :sleep if resident.state.to_s.include?("ねて") || text.include?("ねむった")
      return :eat if text.include?("ごはん")
      return :play if PLAY_WORDS.any? { text.include?(it) }
      return :worry if text.include?("借り") || text.include?("足りない")
      return :sad if resident.mood.to_i < 35 && resident.mood
      return :rich if resident.money.to_i >= 1000
      return :happy if resident.mood.to_i >= 70

      :normal
    end

    # 液晶の中のねこ。pose は POSES の名前
    def pixel_pet(pose, size: 128, label: nil)
      eyes, mouth, mark = POSES.fetch(pose)
      dark = dots(BODY.join("|"))
      light = dots(BODY.join("|"), char: "+")
      EYES.fetch(eyes).each { |x, y, art| dark += dots(art, x:, y:) }
      mx, my, art = MOUTHS.fetch(mouth)
      dark += dots(art, x: mx, y: my)

      tag.svg(class: "pixel-pet pose-#{pose}", viewBox: "0 0 23 16", width: size * 23 / 16, height: size,
              role: "img", "aria-label": label || POSE_LABELS.fetch(pose), "shape-rendering": "crispEdges") do
        safe_join([
          tag.g(class: "pixel-body") { safe_join([ rects(dark, "px-dark"), rects(light, "px-light") ]) },
          (if mark
             art = MARKS.fetch(mark)
             tag.g(class: "pixel-mark") do
               safe_join([ rects(dots(art, x: 17, y: 1), "px-dark"), rects(dots(art, x: 17, y: 1, char: "+"), "px-light") ])
             end
           end)
        ].compact)
      end
    end

    private

    # 点の並び（| で行を区切る）→ 点の座標 "x,y" の配列
    def dots(art, x: 0, y: 0, char: "#")
      art.split("|").each_with_index.flat_map do |row, dy|
        row.chars.each_with_index.filter_map { |c, dx| [ x + dx, y + dy ] if c == char }
      end
    end

    def rects(points, css)
      return "".html_safe if points.empty?

      path = points.map { |x, y| "M#{x} #{y}h1v1h-1z" }.join
      tag.path(d: path, class: css)
    end
  end
end
