# イベントストアの全部のイベントを1回だけ読んで、つながりをたどるための索引を作る（読むだけ）。
#
# RES の読み取り API には「correlation_id で探す」がないので、全部を読んで手元で引く。学習用の小さなストアだから足りる。
# 本物の大きさなら、RES の RubyEventStore::LinkByCorrelationId などを購読して $by_correlation_id_<id> のストリームに
# リンクしておき、そこを読む（書き込みになるので、このパックではやらない。README の「イベントビューア」の節）
module EventViewer
  class EventIndex
    # 1つの業務（振込・注文・出金依頼・二人承認）をまとめるストリーム。口座と商品は出来事が多すぎるのでたどらない
    BUSINESS = /\A(Transfer|Order|WithdrawalRequest|Approval)\$/

    def initialize(event_store: Rails.configuration.event_store)
      @events = {}
      @position = {}
      @by_correlation = Hash.new { |hash, key| hash[key] = [] }
      @by_key = Hash.new { |hash, key| hash[key] = [] }
      event_store.read.in_batches(1000).each_batch { |batch| batch.each { add(it) } }
    end

    def event(id) = @events[id]

    def include?(id) = @events.key?(id)

    # 書かれた順の番号（1 から）
    def position(id) = @position.fetch(id)

    def correlated(correlation_id) = correlation_id ? @by_correlation[correlation_id].map { @events[it] } : []

    # 業務のストリーム（"Transfer$<id>" など）にかかわる出来事を、書かれた順に
    def keyed(key) = @by_key[key].map { @events[it] }

    # この出来事がかかわる業務のストリーム。もともと書かれた先（振込のイベントなら Transfer$）と、
    # data に入っている ID（振込ID・注文ID・出金依頼ID・申請ID）と、metadata の approval_id（承認で実行した銀行のイベント）
    def self.keys(event)
      keys = Catalog::STREAM_FIELDS.except(:sku).filter_map do |field, prefix|
        "#{prefix}#{event.data[field]}" if event.data[field].present?
      end
      keys << "Approval$#{event.metadata[:approval_id]}" if event.metadata[:approval_id].present?
      home = Catalog.home_stream(event)
      keys << home if home&.match?(BUSINESS)
      keys.uniq
    end

    private

    def add(event)
      id = event.event_id
      @events[id] = event
      @position[id] = @position.size + 1
      @by_correlation[event.correlation_id] << id if event.correlation_id
      self.class.keys(event).each { @by_key[it] << id }
    end
  end
end
