# ふせんの壁の表示の手伝い
module EventViewer
  module WallsHelper
    # 処理の出来事を、続けて同じ種類のものは1枚のふせんにまとめる（利息を口座ごとに …）
    def wall_event_chunks(beat) = beat.events.chunk_while { |a, b| a.event_type == b.event_type }.to_a

    # 黄色のふせん（人）。いつもの流れでは、だれでも同じなので「行員」「利用者」まで
    def wall_person(beat, generic:)
      kind = beat.actor.to_s.split(":", 2).first
      generic && EventLens::Names::PEOPLE.key?(kind) ? EventLens::Names::PEOPLE.fetch(kind) : names.actor(beat.actor)
    end

    # 今の絞り込みを残したまま、一部だけ変えた壁へのリンク（nil を渡すと外す）
    def wall_path_with(**changes)
      event_viewer_wall_path(request.query_parameters.merge(changes.transform_keys(&:to_s)).compact_blank)
    end

    # この流れだけを見る（流れの最初の出来事の correlation_id で絞る）
    def wall_row_path(row) = event_viewer_wall_path(correlation: row.events.first.correlation_id)
  end
end
