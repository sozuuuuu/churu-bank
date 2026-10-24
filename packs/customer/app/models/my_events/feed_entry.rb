# 「わたしの出来事」の索引の1行（表 my_event_entries）: この口座の持ち主は、この出来事を見てよい。
# 一覧は出来事を全部読まずに、ここから新しい順に PAGE 件ずつ読む（記帳時刻と行の番号で区切る、続きは before）
module MyEvents
  class FeedEntry < ApplicationRecord
    self.table_name = "my_event_entries"

    PAGE = 50

    # 出来事1件を、見てよい口座ぶん書く（何度呼ばれても増えない）
    def self.record(event)
      rows = Audience.accounts(event).map do |number|
        { account_number: number, event_id: event.event_id, event_type: event.event_type, recorded_at: event.timestamp }
      end
      insert_all(rows, unique_by: %i[account_number event_id]) if rows.any?
    end

    # 口座の出来事を、新しい順に1ページ。同じ出来事が自分の口座2つにかかわっても1回だけ。
    # before は前のページの最後の行の印（cursor）。返すのは [行の配列, 次のページの印（なければ nil）]
    def self.page(account_numbers, types: nil, before: nil, limit: PAGE)
      firsts = where(account_number: account_numbers).group(:event_id).select("MIN(id)")
      scope = where(id: firsts)
      scope = scope.where(event_type: types) if types
      if (at, id = decode(before)) && at
        scope = scope.where("recorded_at < :at OR (recorded_at = :at AND id < :id)", at:, id:)
      end
      rows = scope.order(recorded_at: :desc, id: :desc).limit(limit + 1).to_a
      more = rows.size > limit
      rows = rows.first(limit)
      [ rows, (encode(rows.last) if more) ]
    end

    # 印は「記帳時刻のマイクロ秒_行の番号」（数字だけなので、画面の部品の id にも URL にもそのまま使える）
    def self.encode(row) = "#{(row.recorded_at.to_r * 1_000_000).to_i}_#{row.id}"

    def self.decode(cursor)
      micros, id = cursor.to_s.split("_", 2)
      [ Time.zone.at(Rational(Integer(micros), 1_000_000)), Integer(id) ] if micros.present? && id.present?
    rescue ArgumentError, TypeError
      nil
    end

    # 作り直し: 表を空にして、イベントストアの全部の出来事を書かれた順に流し直す（読み取りモデルなので消してよい）。流した数を返す。
    # 全体を1つのトランザクションにすると、SQLite がそのあいだほかの書き込み（ねこ町など）を止めてしまうので、500 件ずつ書く。
    # 作り直しているあいだは、一覧が途中までになる
    def self.rebuild!(event_store: Rails.configuration.event_store)
      count = 0
      delete_all
      event_store.read.in_batches(500).each_batch do |batch|
        transaction { batch.each { record(it) } }
        count += batch.size
      end
      count
    end
  end
end
