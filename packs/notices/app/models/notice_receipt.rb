# 利用者ごとの「開いた（既読）」と「閉じた（ねこの吹き出しから消した）」。
# 変わったら、その利用者の開いている画面（ほかのタブ）にも refresh を送る
class NoticeReceipt < ApplicationRecord
  belongs_to :notice
  belongs_to :user

  def self.read!(notice, user, at: Time.current)
    receipt = create_or_find_by!(notice:, user:)
    return receipt if receipt.read_at

    receipt.update!(read_at: at)
    Notices::RefreshJob.perform_later(user)
    receipt
  end

  # 閉じたら既読にもする
  def self.dismiss!(notice, user, at: Time.current)
    receipt = create_or_find_by!(notice:, user:)
    return receipt if receipt.dismissed_at

    receipt.update!(dismissed_at: at, read_at: receipt.read_at || at)
    Notices::RefreshJob.perform_later(user)
    receipt
  end
end
