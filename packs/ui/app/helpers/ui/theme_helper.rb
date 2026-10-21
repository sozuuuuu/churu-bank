# 利用者画面（ねこテーマ）の部品: 線画のアイコン、表情を出し分けるねこ、画面下のセリフ窓。
# 利用者向けのパックのベースコントローラで helper Ui::ThemeHelper する（layouts/cat がセリフ窓を出す）
module Ui
  module ThemeHelper
    # ねこの表情。出来事で切り替える（うれしい = 入金・振込完了、びっくり = 確認画面、しょんぼり = 残高不足・組戻し・凍結中）
    CAT_FACES = { normal: "ふつう", happy: "うれしい", surprised: "びっくり", sad: "しょんぼり" }.freeze

    # 線画のアイコン（24×24、線の色は currentColor）。絵文字の代わり
    ICONS = {
      send: '<path d="M3 11 L21 3 L14 21 L11 13 Z"/><path d="M11 13 L21 3"/>',
      calendar: '<rect x="4" y="5" width="16" height="15" rx="3"/><path d="M4 10 h16 M9 3 v4 M15 3 v4"/>',
      passbook: '<rect x="5" y="3" width="14" height="18" rx="2.5"/><path d="M9 8 h6 M9 12 h6 M9 16 h3"/>',
      clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5 V12 l3 2"/>',
      bell: '<path d="M6 16 V11 a6 6 0 0 1 12 0 v5 l1.5 2 h-15 z"/><path d="M10 21 h4"/>',
      fish: '<path d="M3 12 c4 -6 11 -6 15 0 c-4 6 -11 6 -15 0 z"/><path d="M18 12 l3 -3 v6 z"/>' \
            '<circle cx="8" cy="11" r="0.8" fill="currentColor"/>',
      bag: '<path d="M4 9 h16 l-1.5 11 h-13 z"/><path d="M9 9 a3 3 0 0 1 6 0"/>',
      cart: '<path d="M3 4 h2.5 l2 11 h10 l2 -8 H7"/><circle cx="9.5" cy="19" r="1.4"/><circle cx="16.5" cy="19" r="1.4"/>',
      wallet: '<path d="M4 8 h14 a2 2 0 0 1 2 2 v8 a2 2 0 0 1 -2 2 H6 a2 2 0 0 1 -2 -2 z"/><path d="M4 8 l11 -4 v4"/>' \
              '<circle cx="16" cy="14" r="1.2" fill="currentColor"/>',
      arrow_in: '<path d="M12 4 v14 M6 12 l6 6 l6 -6"/>',
      arrow_out: '<path d="M12 20 V6 M6 12 l6 -6 l6 6"/>',
      undo: '<path d="M9 5 L4 10 l5 5"/><path d="M4 10 h10 a5 5 0 0 1 0 10 h-3"/>',
      sprout: '<path d="M12 21 v-9"/><path d="M12 12 c0 -4 -3 -6 -7 -6 c0 4 3 6 7 6 z"/>' \
              '<path d="M12 14 c0 -3 3 -5 7 -5 c0 3 -3 5 -7 5 z"/>',
      letter: '<rect x="3.5" y="6" width="17" height="12.5" rx="2.5"/><path d="M4 7.5 l8 6 l8 -6"/>',
      megaphone: '<path d="M4 10 v4 h3 l8 4 V6 l-8 4 z"/><path d="M18 9.5 a3.5 3.5 0 0 1 0 5"/>',
      heart: '<path d="M12 19 c-6 -4 -8.5 -7 -8.5 -10 a4 4 0 0 1 8.5 -1.5 a4 4 0 0 1 8.5 1.5 c0 3 -2.5 6 -8.5 10 z"/>',
      wrench: '<path d="M14.5 4.5 a4.5 4.5 0 0 0 -4.6 5.9 L4 16.3 a2 2 0 0 0 2.8 2.8 l5.9 -5.9 ' \
              'a4.5 4.5 0 0 0 5.9 -4.6 l-2.8 2.8 l-2.5 -0.5 l-0.5 -2.5 z"/>',
      close: '<path d="M6 6 l12 12 M18 6 L6 18"/>',
      check: '<path d="M5 12.5 l4.5 4.5 L19 7"/>',
      alert: '<path d="M12 3.5 L21 19.5 H3 Z"/><path d="M12 10 v4"/><circle cx="12" cy="16.8" r="0.7" fill="currentColor"/>',
      lock: '<rect x="5" y="11" width="14" height="9.5" rx="2.5"/><path d="M8 11 V8 a4 4 0 0 1 8 0 v3"/>',
      back: '<path d="M10 6 l-6 6 l6 6 M4 12 h16"/>',
      logout: '<path d="M14 4 h4 a2 2 0 0 1 2 2 v12 a2 2 0 0 1 -2 2 h-4"/><path d="M10 8 l-4 4 l4 4 M6 12 h9"/>',
      key: '<circle cx="8" cy="15" r="4"/><path d="M11 12 l8 -8 M16 7 l3 3"/>'
    }.freeze

    # icon(:send) → <svg class="icon icon-send" ...>。飾りなので aria-hidden
    def icon(name, size: 20, css: nil)
      paths = ICONS.fetch(name.to_sym)
      tag.svg(paths.html_safe, class: [ "icon", "icon-#{name.to_s.dasherize}", css ],
                               width: size, height: size, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
                               "stroke-width": 2.2, "stroke-linecap": "round", "stroke-linejoin": "round",
                               "aria-hidden": true, focusable: false)
    end

    # キラッ（塗りの星。色は CSS の --star）。飾り
    def sparkle(size: 20, css: nil, **attributes)
      tag.svg(tag.path(d: "M10 1 l2.4 6.6 l6.6 2.4 l-6.6 2.4 l-2.4 6.6 l-2.4 -6.6 l-6.6 -2.4 l6.6 -2.4 z"),
              class: [ "sparkle", css ], width: size, height: size, viewBox: "0 0 20 20",
              "aria-hidden": true, focusable: false, **attributes)
    end

    # ねこ（主線つき）。4つの表情をまとめて描いておき、data-face で出し分ける（JS で切り替えられる）
    def cat(face: :normal, size: 92, **attributes)
      face = face.to_sym
      raise ArgumentError, "知らない表情: #{face}" unless CAT_FACES.key?(face)

      render "ui/cat", face:, size:, attributes:
    end

    # このページのセリフ（画面下のセリフ窓）。猫語はここだけ。ページのテンプレートで1回呼ぶ
    def cat_says(text, face: :normal)
      content_for :cat_line, text, flush: true
      content_for :cat_face, face.to_s, flush: true
      nil
    end

    # Turbo Frame の中など、レイアウトを通らない所からセリフを変える（Stimulus の cat-say）。
    # その要素が消えると、ページのセリフに戻る
    def cat_say_tag(text, face: :normal, bounce: false)
      tag.span(hidden: true, data: { controller: "cat-say", cat_say_text_value: text, cat_say_face_value: face,
                                     cat_say_bounce_value: bounce })
    end
  end
end
