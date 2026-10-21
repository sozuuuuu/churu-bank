# 銀行からのお知らせ。掲載期間（starts_at〜ends_at）と対象（全員 / 選んだ利用者）で、だれにいつ見えるかが決まる。
# 書き込みは Notices::Board から（行員の画面・seeds・あとでキャンペーン）
class Notice < ApplicationRecord
  # 種類。キャンペーンはここに足す（特典の自動入金は別のパックで、お知らせはそのパックが Board から出す）
  KINDS = {
    "info" => { label: "お知らせ", icon: "📢" },
    "request" => { label: "お願い", icon: "🙏" },
    "maintenance" => { label: "メンテナンス", icon: "🛠️" }
  }.freeze

  AUDIENCES = { "everyone" => "全員", "selected" => "選んだ利用者" }.freeze

  STATUS_LABELS = { scheduled: "掲載前", live: "掲載中", ended: "掲載終了" }.freeze

  has_many :targets, class_name: "NoticeTarget", dependent: :delete_all
  has_many :target_users, through: :targets, source: :user
  has_many :receipts, class_name: "NoticeReceipt", dependent: :delete_all

  validates :kind, inclusion: { in: KINDS.keys, message: "種類を選んでください" }
  validates :audience, inclusion: { in: AUDIENCES.keys, message: "対象を選んでください" }
  validates :title, presence: { message: "タイトルを入れてください" },
                    length: { maximum: 80, message: "タイトルは 80 文字までです" }
  validates :starts_at, presence: { message: "掲載開始を入れてください" }
  validate :ends_after_start
  validate :targets_chosen

  # いま掲載中のもの
  scope :live, ->(at = Time.current) { where(starts_at: ..at).where("notices.ends_at IS NULL OR notices.ends_at > ?", at) }
  # その利用者が対象のもの（全員向けと、その人が選ばれているもの）
  scope :for_user, ->(user) { where(audience: "everyone").or(where(id: NoticeTarget.where(user_id: user.id).select(:notice_id))) }
  # 重要なものを先に、新しいものから
  scope :newest_first, -> { order(important: :desc, starts_at: :desc, id: :desc) }

  def kind_label = KINDS.dig(kind, :label)

  def kind_icon = KINDS.dig(kind, :icon)

  def audience_label = AUDIENCES[audience]

  def everyone? = audience == "everyone"

  def status(at = Time.current)
    if starts_at > at then :scheduled
    elsif ends_at && ends_at <= at then :ended
    else :live
    end
  end

  def status_label(at = Time.current) = STATUS_LABELS[status(at)]

  def ended?(at = Time.current) = status(at) == :ended

  private

  def ends_after_start
    return unless starts_at && ends_at && ends_at < starts_at

    errors.add(:ends_at, "掲載終了は掲載開始より後にしてください")
  end

  def targets_chosen
    errors.add(:target_users, "対象の利用者を選んでください") if audience == "selected" && target_users.empty?
  end
end
