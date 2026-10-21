# ある利用者から見たお知らせ: いま掲載中で自分が対象のもの、未読の数、ねこの吹き出しに出すもの
module Notices
  class Inbox
    attr_reader :customer

    def initialize(customer, at: Time.current)
      @customer = customer
      @at = at
    end

    def notices = @notices ||= Notice.live(@at).for_customer(customer).newest_first.to_a

    def read?(notice) = receipts[notice.id]&.read_at.present?

    def dismissed?(notice) = receipts[notice.id]&.dismissed_at.present?

    def unread = notices.reject { read?(it) }

    def unread_count = unread.size

    # 吹き出しに出すもの: 重要なものは閉じるまで（開いて既読になっても出し続ける）、ふつうのものは未読のあいだ
    def bubble
      notices.reject { dismissed?(it) || (!it.important? && read?(it)) }
    end

    private

    def receipts
      @receipts ||= NoticeReceipt.where(customer:, notice_id: notices.map(&:id)).index_by(&:notice_id)
    end
  end
end
