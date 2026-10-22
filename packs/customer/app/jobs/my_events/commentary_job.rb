# ねこの実況（利用者の画面。TODO の X）: 出来事がコミットされたら（RES の非同期ハンドラ。Solid Queue）、
# その出来事を見てよい利用者（Audience）にだけ、ちゅーるのひとことを1行送る。画面ではセリフ窓がしゃべる（event_lens--commentary）。
# 文は EventLens::Commentary の利用者向け（自分の口座は「あなた」、ほかの人は「ほかのお客さま」、行員の名前は出さない）。
# 購読は customer_stream_from current_customer, :commentary（利用者の接続だけ）。銀行の側はこの係を知らない
module MyEvents
  class CommentaryJob < ApplicationJob
    prepend RailsEventStore::AsyncHandler

    TARGET = "cat_commentary".freeze

    queue_as :default

    def perform(event)
      Audience.of(event).each do |customer|
        line = EventLens::Commentary.new(names: EventsController.names_for(customer),
                                         own_accounts: customer.account_numbers).line(event)
        html = EventsController.render(partial: "event_lens/commentary_line", locals: { event:, line: })
        Turbo::StreamsChannel.broadcast_prepend_to(customer, :commentary, target: TARGET, html:)
      end
    end
  end
end
