# イベントの actor（staff:<id> / customer:<id>）を、画面では名前で出す
module Admin
  module ActorsHelper
    ACTOR_KINDS = { "staff" => "行員", "customer" => "利用者" }.freeze

    def actor_name(actor)
      kind, id = actor.to_s.split(":", 2)
      name = actor_names.dig(kind, id)
      name ? "#{name}（#{ACTOR_KINDS.fetch(kind)}）" : actor.to_s
    end

    private

    def actor_names
      @actor_names ||= {
        "staff" => Staff.pluck(:id, :name).to_h.transform_keys(&:to_s),
        "customer" => Customer.pluck(:id, :name).to_h.transform_keys(&:to_s)
      }
    end
  end
end
