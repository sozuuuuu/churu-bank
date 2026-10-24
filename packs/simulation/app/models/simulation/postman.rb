# 郵便屋（Ractor 1 つ）: 住民の名前と受け口（Ractor::Port）の帳面を持ち、手紙を配る。Erlang の「名前をつけたプロセス」の帳面のつもり。
# 住民は起こし直されるたびに受け口が新しくなるので、見張り役がそのたびに Register で書きなおす。
# 時計役の合図（Tick）や住民の「足りないにゃ」（Trouble）は Broadcast で、みんなへ配る。
# 倒れたばかりの住民の受け口は閉じているので、配れなかった手紙は捨てる（Erlang でも、いないプロセスへの手紙は消える）
module Simulation
  class Postman
    def self.spawn
      Ractor.new(name: "郵便屋") { Postman.new.run }
    end

    def initialize
      @book = {}
    end

    def run
      loop do
        letter = Ractor.receive
        break if letter == :stop

        handle(letter)
      end
    end

    def handle(letter)
      case letter
      when Letters::Register then @book[letter.name] = letter.port
      when Letters::Broadcast
        @book.each { |name, port| deliver(port, letter.letter) unless name == letter.except }
      end
    end

    private

    def deliver(port, letter)
      port << letter
    rescue Ractor::ClosedError
      nil
    end
  end
end
