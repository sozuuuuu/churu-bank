# 窓口チャットの発言。書き込みは Counter::Desk#speak から。消さずに残す
class CounterMessage < ApplicationRecord
  KINDS = %w[text withdrawal_guide].freeze # withdrawal_guide … 行員が「出金依頼の画面へ」を案内した

  belongs_to :ticket, class_name: "CounterTicket", foreign_key: :counter_ticket_id, inverse_of: :messages

  validates :author_role, inclusion: { in: %w[customer staff] }
  validates :kind, inclusion: { in: KINDS }
  validates :body, presence: true, length: { maximum: Counter::Desk::MAX_MESSAGE_LENGTH }

  # チャンネルで流す形（ブラウザは textContent で入れるので、ここでは HTML にしない）
  def to_broadcast
    { type: "message", id:, role: author_role, name: author_name, kind:, body:, at: created_at.in_time_zone.strftime("%H:%M") }
  end
end
