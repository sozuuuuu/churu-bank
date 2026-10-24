# 手紙1通を、画面の「手紙の流れ」に出す [種類, ひとこと] にする（Simulation::Letter::KINDS）。時計の合図などは nil
module Simulation
  module LetterText
    module_function

    def describe(letter)
      case letter
      when Letters::Reply then [ letter.ok ? "reply" : "refuse", letter.message ]
      when Letters::Trouble then [ "trouble", "#{letter.amount} ちゅ〜る足りないにゃ…" ]
      when Letters::Lent then [ "lent", "#{letter.amount} ちゅ〜る貸したよ（借用書）" ]
      when Letters::Case then [ "case", "#{letter.resident}さんのローンの申込（#{letter.amount} ちゅ〜る）を見てください" ]
      when Letters::Decision then [ letter.approve ? "reply" : "refuse", "申込を#{letter.approve ? "承認" : "却下"}します（#{letter.reason}）" ]
      when Letters::AskOverdue then [ "ask", "延滞しているローンを教えてください" ]
      when Letters::Overdue
        [ "reply", letter.items.empty? ? "延滞はありません" : "延滞: #{letter.items.map { "#{it.resident}さん #{it.owed} ちゅ〜る" }.join("・")}" ]
      when Letters::Dun then [ "dun", "#{letter.amount} ちゅ〜る、返してください（督促状）" ]
      when *Letters::REQUESTS then [ "ask", request(letter) ]
      end
    end

    def request(letter)
      case letter
      when Letters::AskBalance then "残高を教えて"
      when Letters::AskSalary then "働いたので、お給料をください"
      when Letters::PayRent then "家賃を払います"
      when Letters::WantTransfer then "#{letter.to}さんへ #{letter.amount} ちゅ〜る振り込みたい（#{letter.memo}）"
      when Letters::WantPurchase then "「#{::ShopProduct.find_by(sku: letter.sku)&.name || letter.sku}」を #{letter.quantity} こ買いたい"
      when Letters::WantFun then "#{Roster.place(letter.place)&.name || letter.place}で遊びたい"
      when Letters::WantLoan then "ちゅ〜るローンで #{letter.amount} ちゅ〜る借りたい"
      when Letters::WantLend then "#{letter.to}さんに #{letter.amount} ちゅ〜る貸したい"
      when Letters::WantRepay
        "#{letter.to == Letters::BANK ? "銀行" : "#{letter.to}さん"}に #{letter.amount} ちゅ〜る返したい"
      end
    end
  end
end
