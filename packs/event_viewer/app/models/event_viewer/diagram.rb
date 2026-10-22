# つながりの図（Tree）とレーン図（Lanes）の座標。Flow を受け取って、SVG に描く位置と線の形（path の d）を決める。
# order は再生ボタンで光る順番（Flow#events の並び = 書かれた順）
module EventViewer
  module Diagram
    Node = Data.define(:event, :x, :y, :order)
    Edge = Data.define(:kind, :d, :order)

    # 角を丸めた折れ線（縦の線の上下で曲がる）。x1,y1 → 縦の線 mx → x2,y2
    def self.elbow(x1, y1, mx, x2, y2, r: 8)
      r = [ r, (y2 - y1).abs / 2.0 ].min
      dir1 = mx >= x1 ? 1 : -1
      dir2 = x2 >= mx ? 1 : -1
      "M #{x1} #{y1} H #{mx - dir1 * r} Q #{mx} #{y1} #{mx} #{y1 + r} V #{y2 - r} Q #{mx} #{y2} #{mx + dir2 * r} #{y2} H #{x2}"
    end

    # つながりの図: 時間は上から下。処理（Step）ごとに枠で囲み、:cause でつながるたびに1列右へ
    class Tree
      NODE_W = 192
      NODE_H = 48
      ROW = 58
      COL = 218
      PAD_X = 30
      PAD_Y = 10
      STEP_LABEL = 22
      STEP_GAP = 18

      StepBox = Data.define(:step, :x, :y, :w, :h)

      attr_reader :nodes, :step_boxes, :edges, :width, :height

      def initialize(flow)
        @flow = flow
        @order = flow.events.each_with_index.to_h { |event, i| [ event.event_id, i ] }
        place
        @edges = flow.links.map { edge(it) }
        @width = PAD_X + (flow.max_depth + 1) * COL
      end

      private

      def place
        @nodes = []
        @step_boxes = []
        @by_id = {}
        y = PAD_Y
        @flow.steps.each do |step|
          x = PAD_X + step.depth * COL
          top = y
          y += STEP_LABEL
          step.events.each do |event|
            node = Node.new(event:, x:, y:, order: @order.fetch(event.event_id))
            @nodes << node
            @by_id[event.event_id] = node
            y += ROW
          end
          bottom = y - (ROW - NODE_H) + 8
          @step_boxes << StepBox.new(step:, x: x - 10, y: top, w: NODE_W + 20, h: bottom - top)
          y = bottom + STEP_GAP
        end
        @height = y
      end

      def edge(link)
        a = @by_id.fetch(link.from)
        b = @by_id.fetch(link.to)
        d = case link.kind
        when :same # 同じ処理の続き: まっすぐ下へ
          "M #{a.x + NODE_W / 2} #{a.y + NODE_H} V #{b.y - 2}"
        when :cause # きっかけ: 右の辺から出て、列のあいだを下りて、次の列の左の辺へ
          Diagram.elbow(a.x + NODE_W, a.y + NODE_H / 2, a.x + NODE_W + 20, b.x - 2, b.y + NODE_H / 2)
        else # そのあと（同じ業務の続き）: 左の外側を回って下へ
          Diagram.elbow(a.x, a.y + NODE_H / 2, [ a.x, b.x ].min - 22, b.x - 2, b.y + NODE_H / 2)
        end
        Edge.new(kind: link.kind, d:, order: @order.fetch(link.to))
      end
    end

    # レーン図: 関係者（もともと書かれたストリーム）を横に並べ、出来事を時間の順に1行ずつ。前の出来事から矢印
    class Lanes
      LANE_W = 138
      HEAD_H = 62
      ROW = 46
      PAD_LEFT = 78
      DOT_R = 7

      Lane = Data.define(:stream, :x)

      attr_reader :lanes, :nodes, :edges, :width, :height

      def initialize(flow)
        @lanes = flow.lanes.each_with_index.map { |stream, i| Lane.new(stream:, x: PAD_LEFT + i * LANE_W + LANE_W / 2) }
        x_of = @lanes.to_h { [ it.stream, it.x ] }
        @nodes = flow.events.each_with_index.map do |event, i|
          Node.new(event:, x: x_of.fetch(flow.lane_of(event)), y: HEAD_H + 26 + i * ROW, order: i)
        end
        by_id = @nodes.index_by { it.event.event_id }
        @edges = flow.links.map { edge(by_id.fetch(it.from), by_id.fetch(it.to), it.kind) }
        @width = PAD_LEFT + @lanes.size * LANE_W + 50 # 右端のレーンの字がはみ出す分
        @height = HEAD_H + 26 + @nodes.size * ROW
      end

      private

      # 上の点から下の点へ、縦にしなる曲線（同じレーンならまっすぐ）
      def edge(a, b, kind)
        y1 = a.y + DOT_R + 1
        y2 = b.y - DOT_R - 3
        bend = (y2 - y1) / 2.0
        d = "M #{a.x} #{y1} C #{a.x} #{y1 + bend} #{b.x} #{y2 - bend} #{b.x} #{y2}"
        Edge.new(kind:, d:, order: b.order)
      end
    end
  end
end
