# イベントの表示: 日本語の名前・種類の色・アイコン・中身の値（金額・口座・だれ・ほかの出来事へのリンク）。
# 使う画面（行員の画面・利用者の画面）は、ヘルパーで次の3つを用意する（リンクしないなら nil を返す）:
#   lens_event_path(event_id) … 出来事の中身へ / lens_lanes_path(stream:) … レーン図へ / lens_time_machine_path(account:) … タイムマシンへ
# names（EventLens::Names）もヘルパーで用意する
module EventLens
  module EventsHelper
    def event_entry(event) = Catalog.entry(event.event_type)

    # 種類の色の CSS クラス（.kind-money-in など）
    def kind_class(kind) = "kind-#{kind.to_s.dasherize}"

    # 秒まで（同じ処理の出来事が並ぶので）
    def event_time(time) = time&.in_time_zone&.strftime("%m/%d %H:%M:%S")

    def event_badge(event, link: true)
      entry = event_entry(event)
      body = safe_join([ icon(entry.icon, size: 16), entry.label ])
      css = [ "event-badge", kind_class(entry.kind) ]
      path = lens_event_path(event.event_id) if link
      path ? link_to(body, path, class: css) : tag.span(body, class: css)
    end

    # 図（SVG）の中に置く線画のアイコン（Ui::ThemeHelper と同じ絵）
    def svg_icon(name, x:, y:, size:)
      tag.svg(Ui::ThemeHelper::ICONS.fetch(name.to_sym).html_safe, x:, y:, width: size, height: size, viewBox: "0 0 24 24",
              class: "ev-svg-icon", fill: "none", stroke: "currentColor", "stroke-width": 2.2,
              "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": true)
    end

    # 一覧の「中身」の欄: 金額・相手・メモ・理由など、目立つものを3つまで
    SUMMARY_FIELDS = %i[amount total quantity from_account to_account account_number counterparty name memo reason summary].freeze

    def event_summary(event)
      data = event.data
      parts = SUMMARY_FIELDS.filter_map do |key|
        next if data[key].blank?
        next if key == :account_number && (data[:from_account] || data[:counterparty])

        case key
        when *Catalog::MONEY_FIELDS then churu(data[key])
        when :quantity then "#{data[key]} 個"
        when :from_account then "#{names.account(data[:from_account])} → #{names.account(data[:to_account])}"
        when :to_account then nil
        when :counterparty then "相手 #{names.account(data[key])}"
        when *Catalog::ACCOUNT_FIELDS then names.account(data[key])
        else truncate(data[key].to_s, length: 30)
        end
      end
      parts.first(3).join("・")
    end

    # 中身の表の値。金額は「120 ちゅ〜る」、口座は名義つき、だれは名前、出来事の ID はその出来事へのリンク
    def field_value(key, value, metadata: false)
      key = key.to_sym
      return tag.span("（なし）", class: "muted") if value.nil? || value == ""

      case key
      when *Catalog::MONEY_FIELDS then churu(value)
      when *Catalog::ACCOUNT_FIELDS then link_or_text(names.account(value), lens_time_machine_path(account: value))
      when *Catalog::ACTOR_FIELDS then names.actor(value)
      when *Catalog::EVENT_FIELDS then event_links(Array(value))
      when :timestamp, :valid_at then l_time(value)
      when :kind then Catalog::APPROVAL_KINDS.fetch(value.to_s, value.to_s)
      when :lines then order_lines(value)
      when :correlation_id then tag.code(value)
      else
        if !metadata && (prefix = Catalog::STREAM_FIELDS[key])
          link_or_text(names.stream("#{prefix}#{value}"), lens_lanes_path(stream: "#{prefix}#{value}"))
        elsif value == true || value == false
          value ? "はい" : "いいえ"
        else
          value.to_s
        end
      end
    end

    def l_time(value)
      time = value.respond_to?(:in_time_zone) ? value : Time.zone.parse(value.to_s)
      time.in_time_zone.strftime("%Y/%m/%d %H:%M:%S.%L")
    rescue ArgumentError, TypeError
      value.to_s
    end

    def link_or_text(text, path) = path ? link_to(text, path) : text

    private

    def event_links(ids)
      safe_join(ids.map { link_or_text("出来事 #{names.short(it)}", lens_event_path(it)) }, "、")
    end

    def order_lines(lines)
      tag.ul(class: "plain") do
        safe_join(Array(lines).map do |line|
          line = line.to_h.symbolize_keys
          tag.li("#{line[:name]} × #{line[:quantity]}（#{churu(line[:unit_price].to_i)}）")
        end)
      end
    end
  end
end
