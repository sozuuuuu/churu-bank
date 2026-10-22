# 窓口の番号札。番号は日ごとに 1 から。書き込みは Counter::Desk から（読み取りは行員の画面 packs/counter_admin も使う）
class CounterTicket < ApplicationRecord
  STATUS_LABELS = {
    "waiting" => "お待ち", "called" => "窓口で対応中", "finished" => "終わり", "returned" => "札を返した"
  }.freeze
  ACTIVE = %w[waiting called].freeze

  belongs_to :customer
  has_many :messages, -> { order(:id) }, class_name: "CounterMessage", dependent: :delete_all, inverse_of: :ticket

  scope :waiting, -> { where(status: "waiting").order(:service_date, :number) }
  scope :called, -> { where(status: "called").order(:called_at) }
  scope :active, -> { where(status: ACTIVE) }
  scope :closed, -> { where.not(status: ACTIVE).order(closed_at: :desc) }

  def status_label = STATUS_LABELS.fetch(status, status)

  def waiting? = status == "waiting"
  def called? = status == "called"
  def active? = ACTIVE.include?(status)

  # 前に何人待っているか（呼ばれたら 0）
  def ahead
    return 0 unless waiting?

    CounterTicket.waiting.where("service_date < :date OR (service_date = :date AND number < :number)", date: service_date, number:).count
  end

  # このチャットに、いまその役（customer / staff）の人がつないでいるか
  def present?(role) = CounterPresence.in_room(room).where(role:).exists?

  # 在席を数える部屋の名前（CounterPresence#room）
  def room = "ticket:#{id}"

  # 呼んだ行員だけが発言できる（ほかの行員は見るだけ）
  def speakable_by_staff?(staff) = called? && staff_id == staff.id
end
