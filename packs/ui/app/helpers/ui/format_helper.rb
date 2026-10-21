# 金額と日時の表示。画面のパックのベースコントローラで helper Ui::FormatHelper する
module Ui
  module FormatHelper
    # 120 → "120 ちゅ〜る"、-30 → "-30 ちゅ〜る"
    def churu(amount, signed: false)
      text = number_with_delimiter(amount)
      text = "+#{text}" if signed && amount.positive?
      "#{text} ちゅ〜る"
    end

    def jp_date(date) = date&.strftime("%Y/%m/%d")

    def jp_time(time) = time&.in_time_zone&.strftime("%Y/%m/%d %H:%M")
  end
end
