# ふせんの壁（イベントストーミング）: 本物の記録から、出来事（オレンジ）・命令（青）・方針と係（紫）・人（黄）のふせんを並べる（読むだけ）。
#
# 組み立て方（EventLens::EventIndex で全部の出来事を1回読む）:
#   - 処理（Beat）… 同じ人（actor）が、同じきっかけで、ほぼ同時に書いた出来事のまとまり（EventLens::Flow の「処理」と同じ決め方）。
#     1つの処理に、黄（人）か紫（係）・青（命令）・オレンジ（出来事）を貼る
#   - 流れ（Row）… correlation_id・causation_id・同じ業務のストリーム（振込ID・注文ID など）でつながる処理を1本にまとめる。
#     壁の1段が1本の流れで、左から右へ時間が進む
#   - 抜け（waiting）… 係が続きを書くはずなのに、まだ続きがない出来事（保留のまま・予約の実行待ちなど）。ピンクのふせんで目立たせる
#   - いつもの流れ（Pattern）… 流れを「だれが・何を頼んで・どの出来事が起きたか」の並びでまとめて数える
module EventViewer
  class Wall
    MAX_ROWS = 30
    SAME_BEAT_WITHIN = EventLens::Flow::SAME_STEP_WITHIN

    B = Banking::Events
    S = Shop::Events
    # 保留の終わり（通す・取り消す・差し止める）
    HELD_ENDS = [ B::TransferReleased, B::TransferCancelled, B::TransferStopped ].map(&:name).freeze
    # data の中で、ほかの出来事の ID を指している項目（causation_id は metadata なので別に見る）
    REFERENCES = EventLens::Catalog::EVENT_FIELDS - %i[causation_id]

    Beat = Data.define(:events, :actor, :cause, :command, :policy, :waiting) do
      def time = events.first.timestamp

      # 人のふせん（黄）を貼るか。係（紫）のときは貼らない
      def person? = policy.nil?

      # いつもの流れで比べるときの「だれ」: 人は 行員 / 利用者 まで（だれでも同じ流れ）、係はその係
      def who = policy&.label || actor.to_s.split(":", 2).first
    end

    Row = Data.define(:beats) do
      def events = beats.flat_map(&:events)
      def started_at = beats.first.time
      def ended_at = beats.last.events.last.timestamp

      # レーン図にできる業務のストリーム。頼む側（注文・申請・出金依頼）を先に、なければ振込。口座だけの流れ（入金など）は nil
      def business_key
        keys = events.flat_map { EventLens::EventIndex.keys(it) }.uniq
        keys.find { it.match?(EventLens::Flow::ORCHESTRATORS) } || keys.first
      end

      def waiting? = beats.any?(&:waiting)

      def signature = beats.map { [ it.who, it.command, it.events.map(&:event_type).uniq ] }
    end

    # いつもの流れ: 同じ並びの流れ（rows、新しい順）。ふせんは最新の1本（sample）で見せる
    Pattern = Data.define(:rows) do
      def sample = rows.first
      def count = rows.size
    end

    attr_reader :correlation, :from, :to, :kind

    def initialize(correlation: nil, from: nil, to: nil, kind: nil, index: EventLens::EventIndex.new)
      @correlation = correlation.presence
      @from = parse_date(from)
      @to = parse_date(to)
      @kind = EventLens::Catalog::KINDS.key?(kind&.to_sym) ? kind.to_sym : nil
      @index = index
    end

    def filtered? = [ correlation, from, to, kind ].any?

    # 絞り込んだ流れ（新しい順）
    def matching = @matching ||= all_rows.select { match?(it) }.reverse

    # 壁に貼る流れ（多すぎたら新しいものから MAX_ROWS 本）
    def rows = matching.first(MAX_ROWS)

    def truncated? = matching.size > MAX_ROWS

    # いつもの流れ（多い順。同じ数なら新しい順）
    def patterns
      @patterns ||= matching.group_by(&:signature).values.map { Pattern.new(rows: it) }
                            .sort_by.with_index { |pattern, i| [ -pattern.count, i ] }
    end

    # 種類で絞り込んだとき、薄くしない出来事か
    def highlighted?(event) = kind.nil? || EventLens::Catalog.entry(event.event_type).kind == kind

    private

    def match?(row)
      events = row.events
      return false if correlation && events.none? { it.correlation_id == correlation || it.event_id == correlation }
      return false if from && row.started_at < from.beginning_of_day
      return false if to && row.started_at > to.end_of_day
      return false if kind && events.none? { highlighted?(it) }

      true
    end

    def all_rows
      @all_rows ||= begin
        groups = beats(@index.events)
        connect(groups).map { |members| build_row(members.map { groups[it] }) }
      end
    end

    # 処理に分ける。同じ人・同じきっかけ・ほぼ同時に加えて、同じ publish（correlation_id）か、
    # 同じ入れ物・業務にかかわるか、すぐ前と同じ種類のこまごました出来事のときだけ、ひとまとまりにする
    # （RES は publish ごとに correlation_id を変えるので、1回のトランザクションでも correlation_id はそろわない）
    def beats(events)
      events.each_with_object([]) do |event, groups|
        last = groups.last
        if last && same_beat?(last, event)
          last << event
        else
          groups << [ event ]
        end
      end
    end

    def same_beat?(group, event)
      prev = group.last
      return false unless prev.metadata[:actor] == event.metadata[:actor] &&
                          prev.metadata[:causation_id] == event.metadata[:causation_id] &&
                          (event.timestamp - prev.timestamp).abs < SAME_BEAT_WITHIN

      same_kind_of_chore?(prev, event) || group.any? { it.correlation_id == event.correlation_id } ||
        group.flat_map { beat_keys(it) }.intersect?(beat_keys(event))
    end

    # 業務のストリームを持たない同じ種類の出来事が続く（利息を口座ごとに・口座をいくつか開く）。
    # 出金依頼などは依頼ごとに別の業務なので、続けて頼んでも別の処理
    def same_kind_of_chore?(prev, event)
      prev.event_type == event.event_type && EventLens::EventIndex.keys(prev).empty? && EventLens::EventIndex.keys(event).empty?
    end

    def beat_keys(event) = [ *EventLens::EventIndex.keys(event), EventLens::Catalog.home_stream(event) ].compact

    # 処理どうしを、同じ correlation_id・きっかけの出来事・同じ業務のストリームでつなぐ（union-find）。
    # つながった処理の番号の束を、最初の処理の順に返す
    def connect(groups)
      parent = Array.new(groups.size) { it }
      root = ->(i) { parent[i] == i ? i : (parent[i] = root.(parent[i])) }
      join = ->(i, j) { parent[root.(i)] = root.(j) if j }
      owner = {}
      beat_of = {}

      groups.each_with_index do |events, i|
        events.each do |event|
          beat_of[event.event_id] = i
          join.(i, beat_of[event.metadata[:causation_id]])
          # 取り消した出来事・取り消す通帳の行 など、中身で指している出来事
          REFERENCES.each { |field| Array(event.data[field]).each { join.(i, beat_of[it]) } }
          [ "correlation:#{event.correlation_id}", *EventLens::EventIndex.keys(event) ].each do |key|
            owner.key?(key) ? join.(i, owner[key]) : owner[key] = i
          end
        end
      end
      groups.each_index.group_by { root.(it) }.values
    end

    def build_row(groups)
      events = groups.flatten
      in_row = events.index_by(&:event_id)
      caused = events.filter_map { it.metadata[:causation_id] }.to_set

      beats = groups.map do |group|
        actor = group.first.metadata[:actor]
        cause = group.filter_map { in_row[it.metadata[:causation_id]] }.find { !group.include?(it) }
        Beat.new(events: group, actor:, cause:, command: WallWords.command(group), policy: WallWords.policy(actor),
                 waiting: waiting(group, events, caused))
      end
      Row.new(beats:)
    end

    # この処理のあと、係が続きを書くはずなのに、まだ続きがないとき、その説明（ピンクのふせん）
    def waiting(group, row_events, caused)
      types = row_events.map(&:event_type)
      group.each do |event|
        case event
        when B::TransferDebited, B::TransferReleased
          next if caused.include?(event.event_id)
          next if group.any?(B::TransferHeld) && types.intersect?(HELD_ENDS)
          return "保留中: 行員が確かめて「通す」のを待っています" if group.any?(B::TransferHeld)

          return "続きの出来事がまだありません（振込の確定の係が動いていない？）"
        when B::TransferScheduled
          later = row_events.drop_while { it != event }.drop(1)
          return "予約中: 実行日（#{event.data[:execute_on]}）を待っています" if later.none? { it.data[:transfer_id] == event.data[:transfer_id] }
        when B::TransferCompleted, B::TransferFailed
          next if caused.include?(event.event_id) || !shop_transfer?(event, row_events)

          return "続きの出来事がまだありません（商店の支払いの係が動いていない？）"
        end
      end
      nil
    end

    def shop_transfer?(event, row_events)
      row_events.any? do |other|
        (other.is_a?(S::OrderPaymentRequested) || other.is_a?(S::OrderRefundRequested)) && other.data[:transfer_id] == event.data[:transfer_id]
      end
    end

    def parse_date(value)
      Date.iso8601(value.to_s).in_time_zone if value.present?
    rescue Date::Error
      nil
    end
  end
end
