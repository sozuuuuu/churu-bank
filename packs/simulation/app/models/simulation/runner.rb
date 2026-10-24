# 町を動かす係（bin/rails churu:simulate）。Puma とは別のプロセスで、メインの Ractor が「役場」になる。
#
#   役場の受け口（hall）に届く手紙を、1通ずつ順に片づける（ActiveRecord を使うのはこの糸だけ）
#     :check（1秒ごと）… 表 simulation_controls を読む。画面で「動かす」なら町を起こし、「止める」なら止め、速さが変わったら時計役へ
#     Tick … 窓口役にいまの日を教え、画面の時計を書き直す。朝なら商店の仕入れ（足りない商品を入荷）
#     Ask… / Want… / PayRent … 窓口役に確かめさせて書き、住民の受け口へ返事を出す。住民どうしの貸し借りが通ったら、
#                               借りた住民へ「貸してもらえたよ」（Lent）を郵便屋に届けてもらう
#     Report / Restarted / Copy … 画面の係（Board）へ（Copy は郵便屋が出す、住民どうしの手紙の写し）
#   手紙（時計の合図のほか）は、画面の「手紙の流れ」にも書き残す
#
# 窓口役が手紙を1通ずつ順に書くので、住民どうしが同時に同じ口座へ書くことはない（それでも銀行の expected_version が守る）
module Simulation
  class Runner
    CHECK_EVERY = 1 # 秒

    def initialize(out: $stdout, board: Board.new)
      @out = out
      @board = board
      @hall = Ractor::Port.new
      @shutdown = false
    end

    def run
      Roster.setup!
      trap_signals
      log "ねこ町の係が起きました。行員の画面 /admin/town から動かせます（止めるのは Ctrl-C）"
      ticker = Thread.new { loop { sleep CHECK_EVERY; @hall << :check } }
      loop do
        break if handle(@hall.receive) == :shutdown
      rescue ActiveRecord::StatementTimeout, ActiveRecord::Deadlocked => e
        # ほかのプロセスが長く書いていて SQLite がロックしていた。この手紙はあきらめて、町は動かし続ける
        log "役場: データベースが混んでいたので、手紙を1通あきらめました（#{e.class.name.demodulize}）"
      end
    ensure
      ticker&.kill
      stop_town
      Control.current.update!(town_running: false, heartbeat_at: nil)
      log "ねこ町の係はおやすみします"
    end

    def handle(letter)
      case letter
      when :check then check
      when Letters::Tick then tick(letter)
      when *Letters::REQUESTS then answer(letter)
      when Letters::Report then @board.report(letter)
      when Letters::Copy then @board.letter(letter.from, letter.to, letter.letter)
      when Letters::Restarted
        log "見張り役: #{letter.name}を起こし直しました（#{letter.count} 回目。#{letter.reason}）"
        @board.restarted(letter)
      end
    end

    private

    def check
      return :shutdown if @shutdown

      control = Control.current
      control.update!(heartbeat_at: Time.current)
      if control.running && !@town
        start_town(control)
      elsif !control.running && @town
        stop_town
        @board.status
      elsif @town && control.seconds_per_day != @seconds_per_day
        @town.speed = @seconds_per_day = control.seconds_per_day
        log "時計役: 1日を #{@seconds_per_day} 秒にしました"
      end
    end

    def start_town(control)
      statuses = ResidentStatus.order(:id).includes(:customer).to_a
      @teller = Teller.new(residents: statuses.index_by(&:name), employer_account: control.employer_account,
                           landlord_account: control.landlord_account, places: control.places || {})
      @seconds_per_day = control.seconds_per_day
      @board.reset
      @town = Town.new(specs: Roster.specs(statuses), hall: @hall, seconds_per_day: @seconds_per_day,
                       day: control.day + 1).start
      control.update!(town_running: true, time: nil)
      @board.status
      log "町を動かしました（住民 #{statuses.size} 匹、1日 #{@seconds_per_day} 秒、#{control.day + 1} 日目から）"
    end

    def stop_town
      return unless @town

      @town.stop
      @town = nil
      drain
      Control.current.update!(town_running: false)
      log "町を止めました"
    end

    # 町が止まったあと、受け口に残っている手紙（住民の最後の様子など）を片づける。
    # 受け口には「まだ残っていますか」と聞く手立てがないので、自分あてに目印を出して、それが届くまで読む
    def drain
      @hall << :drained
      while (letter = @hall.receive) != :drained
        handle(letter) unless letter == :check
      end
    end

    def tick(letter)
      @teller&.today = letter
      @board.clock(letter)
      Roster.restock if letter.time == :morning
    rescue Shop::Error, Banking::Error => e
      log "仕入れ係: 入荷できませんでした（#{e.message}）"
    end

    def answer(letter)
      @board.letter(letter.from, Board::TELLER, letter)
      reply = reply_for(letter)
      @board.letter(Board::TELLER, letter.from, reply)
      deliver_lent(letter) if reply.ok && letter.is_a?(Letters::WantLend)
      @board.debts if reply.ok && Board::MONEY_LETTERS.include?(letter.class)
      letter.reply_to << reply
    rescue Ractor::ClosedError
      nil # 返事を待たずに倒れた住民。起こし直された住民は残高を聞き直す
    end

    # 住民どうしで貸したら、借りた住民へ「貸してもらえたよ」（郵便屋が届け、写しが手紙の流れに出る）
    def deliver_lent(letter)
      @town&.deliver(letter.to, Letters::Lent.new(from: letter.from, amount: letter.amount))
    end

    def reply_for(letter)
      return Letters::Reply.new(request: letter, ok: false, message: "窓口はしまっています") unless @teller

      @teller.handle(letter)
    rescue StandardError => e
      log "窓口役: #{letter.class.name.demodulize} を書けませんでした（#{e.class}: #{e.message}）"
      Letters::Reply.new(request: letter, ok: false, message: "窓口でまちがいがありました")
    end

    def trap_signals
      %w[INT TERM].each { |signal| Signal.trap(signal) { @shutdown = true } }
    end

    def log(message) = @out.puts("[ねこ町 #{Time.current.strftime('%H:%M:%S')}] #{message}")
  end
end
