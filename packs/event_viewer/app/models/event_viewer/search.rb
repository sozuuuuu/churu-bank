# 一覧の絞り込み（種類・口座・日付）。新しいものから PER_PAGE 件ずつ、RES の読み取り API で読む
module EventViewer
  class Search
    PER_PAGE = 50

    attr_reader :kind, :account, :date, :before

    def initialize(kind: nil, account: nil, date: nil, before: nil, event_store: Rails.configuration.event_store)
      @kind = Catalog::KINDS.key?(kind&.to_sym) ? kind.to_sym : nil
      @account = account.presence
      @date = parse_date(date)
      @before = before.presence
      @event_store = event_store
    end

    def filtered? = [ kind, account, date ].any?

    def events = page.first(PER_PAGE)

    # 「もっと前」のリンクに使う、このページのいちばん古い出来事（次のページがなければ nil）
    def next_before = page.size > PER_PAGE ? events.last.event_id : nil

    private

    def page
      @page ||= begin
        scope = @event_store.read.backward
        scope = scope.stream("Account$#{account}") if account
        scope = scope.of_type(Catalog.types_of(kind)) if kind
        scope = scope.newer_than_or_equal(date.beginning_of_day).older_than_or_equal(date.end_of_day) if date
        scope = scope.from(before) if before
        scope.limit(PER_PAGE + 1).to_a
      rescue RubyEventStore::EventNotFound
        []
      end
    end

    def parse_date(value)
      Date.iso8601(value.to_s).in_time_zone if value.present?
    rescue Date::Error
      nil
    end
  end
end
