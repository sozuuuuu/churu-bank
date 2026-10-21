# お知らせを出す・直す・掲載を終える唯一の入口。行員の画面と seeds が使い、あとでキャンペーンのパックも
# 「特典が届いたにゃ」のような、その人向けのお知らせをここから出す。
#
#   board = Notices::Board.new(actor: "admin:#{Current.user.email_address}")
#   board.post(kind: "info", title: "…", body: "…")                       # 全員に、いまから
#   board.post(kind: "request", title: "…", users: [ user ], important: true) # 選んだ利用者に、閉じるまで
#   board.revise(notice, title: "…")
#   board.close(notice)                                                    # 掲載を終える（ends_at を今に）
#
# post / revise は Notice を返す。保存できなかったら persisted? / errors で分かる（例外にしない。フォームで出すため）。
# 保存したら、開いている利用者画面に refresh（morph）を送る。掲載の始まり・終わりが先なら、その時刻にも送る
module Notices
  class Board
    def initialize(actor:)
      @actor = actor
    end

    # users: 対象の利用者（User の配列）。target_user_ids: フォームからの ID。どちらもなければ全員
    def post(**attrs)
      attrs[:audience] ||= attrs.key?(:users) || attrs.key?(:target_user_ids) ? "selected" : "everyone"
      save(Notice.new(posted_by: @actor, starts_at: Time.current), attrs)
    end

    def revise(notice, **attrs) = save(find(notice), attrs)

    # まだ始まっていないものを終えるときは、始まりも今にする（終わりが始まりより前にならないように）
    def close(notice, at: Time.current)
      notice = find(notice)
      return notice if notice.ended?(at)

      notice.update!(starts_at: [ notice.starts_at, at ].min, ends_at: at)
      refresh(notice)
      notice
    end

    private

    def find(notice) = notice.is_a?(Notice) ? notice : Notice.find(notice)

    def save(notice, attrs)
      attrs = attrs.to_h.symbolize_keys
      users = attrs.delete(:users)
      ids = attrs.delete(:target_user_ids)
      saved = Notice.transaction do
        notice.assign_attributes(attrs)
        # 対象は保存済みのお知らせだとすぐ書き込まれるので、保存できなければ巻き戻す
        if notice.audience == "selected"
          notice.target_users = users || User.where(id: Array(ids).compact_blank) unless users.nil? && ids.nil?
        else
          notice.target_users = []
        end
        notice.save || raise(ActiveRecord::Rollback)
      end
      refresh(notice) if saved
      notice
    end

    def refresh(notice)
      RefreshJob.perform_later
      [ notice.starts_at, notice.ends_at ].compact.select(&:future?).each do |at|
        RefreshJob.set(wait_until: at).perform_later
      end
    end
  end
end
