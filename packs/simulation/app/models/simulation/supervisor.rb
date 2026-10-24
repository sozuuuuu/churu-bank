# 見張り役（Ractor 1 つ）: 住民の Ractor を作り、見張り（Ractor#monitor）、倒れたら起こし直す。Erlang の supervisor の one_for_one のつもり。
#
#   住民を作る → 見張り用の受け口を1つずつ作って monitor → 郵便屋の帳面に住民の受け口を書く
#   Ractor.select で「自分あての手紙」と「見張りの知らせ」を同時に待つ
#     :aborted（例外で倒れた）… 倒れたわけ（Ractor#value の例外）を役場へ知らせ、回数を足して作り直す
#     :exited（ふつうに終わった）… 作り直さない
#   :stop が届いたら、住民みんなに :stop を出して、終わるのを待ってから自分も終わる
#
# 起こし直すと住民の記憶ははじめから。所持金の見込みは、起きた住民が窓口役に聞き直す
module Simulation
  class Supervisor
    Child = Data.define(:spec, :ractor, :restarts)

    def self.spawn(specs:, hall:, postman:)
      Ractor.new(specs, hall, postman, name: "見張り役") do |resident_specs, town_hall, post|
        Supervisor.new(specs: resident_specs, hall: town_hall, postman: post).run
      end
    end

    def initialize(specs:, hall:, postman:)
      @specs = specs
      @hall = hall
      @postman = postman
      @children = {} # 見張りの受け口 => Child
    end

    def run
      @specs.each { start(it, restarts: 0) }
      mailbox = Ractor.current.default_port
      loop do
        port, letter = Ractor.select(mailbox, *@children.keys)
        if port.equal?(mailbox)
          break stop_children if letter == :stop

          poke(letter) if letter.is_a?(Letters::Poke)
        else
          watched(port, letter)
        end
      end
    end

    private

    def start(spec, restarts:)
      ractor = Resident.spawn(spec, restarts:, hall: @hall, postman: @postman)
      watch = Ractor::Port.new
      ractor.monitor(watch)
      @postman << Letters::Register.new(name: spec.name, port: ractor.default_port)
      @children[watch] = Child.new(spec:, ractor:, restarts:)
    end

    def watched(port, status)
      child = @children.delete(port)
      port.close
      return unless status == :aborted

      count = child.restarts + 1
      @hall << Letters::Restarted.new(name: child.spec.name, count:, reason: reason(child.ractor))
      start(child.spec, restarts: count)
    end

    # 倒れたわけ。Ractor#value は、中で上がった例外を Ractor::RemoteError に包んで上げなおす
    def reason(ractor)
      ractor.value
      "わからない"
    rescue Ractor::RemoteError => e
      e.cause ? "#{e.cause.message}（#{e.cause.class.name}）" : e.message
    end

    def poke(letter)
      child = @children.each_value.find { it.spec.name == letter.name }
      child&.ractor&.send(letter.letter)
    rescue Ractor::ClosedError
      nil
    end

    def stop_children
      @children.each_value do |child|
        child.ractor.send(:stop)
      rescue Ractor::ClosedError
        nil
      end
      @children.each_key do |watch|
        watch.receive
        watch.close
      end
    end
  end
end
