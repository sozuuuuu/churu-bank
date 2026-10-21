# お知らせが出た・直った・掲載が始まった / 終わったら、開いている利用者画面に Turbo の refresh（morph）を送る。
# 利用者を渡したら、その人の画面だけ（既読・閉じたのを、ほかのタブにも映す）。
# refresh は「ページを取り直して」という合図だけで中身を運ばないので、対象外の人に届いても何も漏れない
module Notices
  class RefreshJob < ApplicationJob
    queue_as :default

    def perform(user = nil)
      if user
        Turbo::StreamsChannel.broadcast_refresh_to(user, :notices)
      else
        Turbo::StreamsChannel.broadcast_refresh_to("notices")
      end
    end
  end
end
