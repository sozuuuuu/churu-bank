# 郵便屋（Ractor 1 つ）: 住民の名前と受け口（Ractor::Port）の帳面を持ち、手紙を配る。Erlang の「名前をつけたプロセス」の帳面のつもり。
# 住民は起こし直されるたびに受け口が新しくなるので、見張り役がそのたびに Register で書きなおす。
# 時計役の合図（Tick）や住民の「足りないにゃ」（Trouble）は Broadcast で、みんなへ配る。
# 役場が「貸してもらえたよ」（Lent）を届けるときは Deliver で1匹へ。
# 住民どうしの手紙（時計の合図のほか）は、写し（Copy）を役場へも出す（画面の「手紙の流れ」。Erlang の observer のつもり）。
# 倒れたばかりの住民の受け口は閉じているので、配れなかった手紙は捨てる（Erlang でも、いないプロセスへの手紙は消える）
module Simulation
  class Postman
    EVERYONE = "みんな"

    def self.spawn(hall:)
      Ractor.new(hall, name: "郵便屋") { |town_hall| Postman.new(hall: town_hall).run }
    end

    def initialize(hall:)
      @hall = hall
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
        copy(letter.letter, EVERYONE) if letter.letter.respond_to?(:from)
      when Letters::Deliver
        port = @book[letter.to]
        deliver(port, letter.letter) if port
        copy(letter.letter, letter.to) if letter.letter.respond_to?(:from)
      end
    end

    private

    def copy(letter, to)
      @hall << Letters::Copy.new(from: letter.from, to:, letter:)
    end

    def deliver(port, letter)
      port << letter
    rescue Ractor::ClosedError
      nil
    end
  end
end
