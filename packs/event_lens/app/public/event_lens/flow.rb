# 1つの出来事から「ひとつながりの出来事」を集めて、つながりの図とレーン図にできる形にする（読むだけ）。
#
# 集め方（EventIndex を使う）:
#   - 同じ correlation_id の出来事（ジョブが CorrelatedHandler で引き継ぐ。振込の入金・商店の引き当てなど）
#   - causation_id の先（きっかけの出来事）
#   - 同じ業務のストリームにかかわる出来事（同じ振込ID・注文ID・出金依頼ID・申請ID）。
#     同じトランザクションで書いた出来事どうし（引き落としと振込の受付など）や、行員があとで「通す」「承認」した出来事は
#     correlation_id がつながっていないので、ここで拾う
#
# 図の形:
#   - 「処理」（Step）… 同じ人（actor）が、同じきっかけで、ほぼ同時（0.5 秒以内）に書いた出来事のまとまり。
#     ふつうは1回のトランザクション（目安。RES はトランザクションの区切りを残さない）
#   - 処理どうしのつながり … :cause（causation_id。ある出来事がきっかけで、ジョブが次の処理をした）/
#     :then（きっかけは記録されていないが、同じ業務の続き。人があとで操作したなど）。処理の中は :same（同じ処理の続き）
#   - 深さ（depth）… :cause でつながるたびに1つ右へ。連鎖が階段のように見える
module EventLens
  class Flow
    MAX_EVENTS = 120
    SAME_STEP_WITHIN = 0.5 # 秒

    Step = Data.define(:index, :events, :actor, :depth, :parent_id, :edge)
    Link = Data.define(:from, :to, :kind)

    # 関係者のレーンを左に寄せる業務（振込を頼む側）
    ORCHESTRATORS = /\A(Order|Approval|WithdrawalRequest)\$/

    class NotFound < StandardError; end

    # only: 見せてよい出来事か（利用者の画面は自分の口座にかかわるものだけ）。見せない出来事も、つながりをたどるときは通り抜ける。
    # 起点の出来事が見せられなければ NotFound
    def self.around(event_id, index: EventIndex.new, only: nil)
      event = index.event(event_id)
      raise NotFound, "出来事 #{event_id} はありません" unless event && (only.nil? || only.call(event))

      new(event, index:, only:)
    end

    # 業務のストリーム（"Transfer$<id>" など）のひとつながり。最初の出来事から集める
    def self.of_stream(stream_name, index: EventIndex.new, only: nil)
      first = index.keyed(stream_name).find { only.nil? || only.call(it) } or raise NotFound, "#{stream_name} の出来事はありません"
      new(first, index:, only:)
    end

    attr_reader :seed, :events, :steps

    def initialize(seed, index:, only: nil)
      @seed = seed
      @index = index
      @events = collect.select { only.nil? || only.call(it) }.sort_by { index.position(it.event_id) }
      @steps = build_steps
    end

    def truncated? = @truncated

    def position(event) = @index.position(event.event_id)

    def step_of(event_id) = @step_by_event.fetch(event_id)

    # 出来事へ入ってくるつながり（最初の出来事は nil）
    def link_to(event_id) = links_by_target[event_id]

    def links = links_by_target.values

    def max_depth = steps.map(&:depth).max || 0

    # レーン図の関係者（出来事がもともと書かれたストリーム）。頼む側（注文・申請・出金依頼）を左に、あとは出てきた順
    def lanes
      streams = events.map { lane_of(it) }.uniq
      streams.each_with_index.sort_by { |stream, i| [ stream.match?(ORCHESTRATORS) ? 0 : 1, i ] }.map(&:first)
    end

    def lane_of(event) = Catalog.home_stream(event) || "?"

    private

    def collect
      found = {}
      queue = [ @seed ]
      while (event = queue.shift)
        next if found.key?(event.event_id)
        if found.size >= MAX_EVENTS
          @truncated = true
          break
        end

        found[event.event_id] = event
        queue.concat(@index.correlated(event.correlation_id))
        if (cause = @index.event(event.metadata[:causation_id]))
          queue << cause
        end
        EventIndex.keys(event).each { queue.concat(@index.keyed(it)) }
      end
      found.values
    end

    def build_steps
      @step_by_event = {}
      groups = events.slice_when { |a, b| !same_step?(a, b) }.to_a
      groups.each_with_index.map do |group, i|
        parent_id, edge, depth = parent_of(group)
        Step.new(index: i, events: group, actor: group.first.metadata[:actor], depth:, parent_id:, edge:).tap do |step|
          group.each { @step_by_event[it.event_id] = step }
        end
      end
    end

    def same_step?(a, b)
      a.metadata[:actor] == b.metadata[:actor] && a.metadata[:causation_id] == b.metadata[:causation_id] &&
        (b.timestamp - a.timestamp).abs < SAME_STEP_WITHIN
    end

    # [つながる先の出来事の ID, :cause / :then, 深さ]
    def parent_of(group)
      cause_id = group.filter_map { it.metadata[:causation_id] }.find { @step_by_event.key?(it) }
      return [ cause_id, :cause, @step_by_event[cause_id].depth + 1 ] if cause_id

      earlier = @step_by_event.keys
      return [ nil, nil, 0 ] if earlier.empty?

      keys = group.flat_map { keys_of(it) }
      related = earlier.reverse.find { (keys_of(@index.event(it)) & keys).any? } || earlier.last
      [ related, :then, @step_by_event[related].depth ]
    end

    def keys_of(event) = [ *EventIndex.keys(event), Catalog.home_stream(event) ].compact

    def links_by_target
      @links_by_target ||= steps.each_with_object({}) do |step, links|
        first, *rest = step.events
        links[first.event_id] = Link.new(from: step.parent_id, to: first.event_id, kind: step.edge) if step.parent_id
        [ first, *rest ].each_cons(2) { |a, b| links[b.event_id] = Link.new(from: a.event_id, to: b.event_id, kind: :same) }
      end
    end
  end
end
