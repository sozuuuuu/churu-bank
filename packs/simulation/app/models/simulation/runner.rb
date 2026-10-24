# 町を動かす係（bin/rails churu:simulate）。Puma とは別のプロセスで、メインの Ractor が「役場」になる。
#
#   役場の受け口（hall）に届く手紙を、1通ずつ順に片づける（ActiveRecord を使うのはこの糸だけ）
#     :check（1秒ごと）… 表 simulation_controls を読む。画面で「動かす」なら町を起こし、「止める」なら止め、速さが変わったら時計役へ
#     Tick … 窓口役にいまの日を教え、画面の時計を書き直す。朝なら商店の仕入れ（足りない商品を入荷）
#     Ask… / Want… / PayRent … 窓口役に確かめさせて書き、住民の受け口へ返事を出す。住民どうしの貸し借りが通ったら、
#                               借りた住民へ「貸してもらえたよ」（Lent）を郵便屋に届けてもらう
#     WantLoan（行員エージェントがいるとき）… すぐには貸さない。申込（LoanCase）を書いて、窓口のたまへ Case を届け、
#                                            住民の受け口は @pending に持っておく。Decision が来たら貸すか断って、そこで返事を出す（非同期）
#     Decision … 行員の決裁。承認ならその行員の actor で貸す
#     AskOverdue … 延滞しているローンを係長に返す（督促状は係長が郵便屋で住民へ出す）
#     Report / ClerkReport / Restarted / Copy … 画面の係（Board）へ（Copy は郵便屋が出す、住民どうし・行員どうしの手紙の写し）
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
      @clerks = {}  # 名前 => ClerkStatus（行員エージェント）
      @pending = {} # 申込の id => WantLoan（決裁を待っている住民の手紙。受け口を持っている）
    end

    def run
      Roster.setup!
      trap_signals
      log "ねこ町の係が起きました。行員の画面 /admin/town から動かせます（止めるのは Ctrl-C）"
      ticker = Thread.new { loop { sleep CHECK_EVERY; @hall << :check } }
      loop { break if handle(@hall.receive) == :shutdown }
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
      when Letters::WantLoan then @clerks.empty? || !@town ? answer(letter) : apply(letter)
      when *Letters::REQUESTS then answer(letter)
      when Letters::Decision then decide(letter)
      when Letters::AskOverdue then overdue(letter)
      when Letters::Report then @board.report(letter)
      when Letters::ClerkReport then @board.clerk(letter)
      when Letters::Copy then copied(letter)
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
      clerks = ClerkStatus.order(:id).includes(:staff).to_a
      @clerks = clerks.index_by(&:name)
      @pending = {}
      LoanCase.pending.update_all(status: "withdrawn", reason: "町が止まったので取り下げ")
      @board.reset
      @town = Town.new(specs: Roster.specs(statuses) + Roster.clerk_specs(clerks), hall: @hall,
                       seconds_per_day: @seconds_per_day, day: control.day + 1).start
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

    # ---- 行員エージェント ----

    # ローンの申込: 申込を書き、窓口（いなければ係長）へ Case を届ける。返事は決裁が来てから
    def apply(letter)
      @board.letter(letter.from, Board::TELLER, letter)
      resident = ResidentStatus.find_by(name: letter.from)
      return letter.reply_to << reply_for(letter) unless resident

      kase = LoanCase.create!(resident: resident.name, amount: letter.amount.to_i, status: "applied", day: today)
      @pending[kase.id] = letter
      reviewer = @clerks.values.find { !it.chief? } || @clerks.values.first
      @town.deliver(reviewer.name, Letters::Case.new(
        id: kase.id, from: Board::TELLER, resident: resident.name, amount: kase.amount,
        owed: ::Loan.owed_by(resident.account_number), salary: Temperament.fetch(resident.temperament).salary,
        overdue: LoanCase.overdue(today).count { it.resident == resident.name }
      ))
    rescue Ractor::ClosedError
      nil
    end

    # 行員の決裁: 承認ならその行員の actor で貸し、断るならわけを添えて、住民へ返事
    def decide(decision)
      @board.letter(decision.from, Board::TELLER, decision)
      kase = LoanCase.find_by(id: decision.case_id)
      letter = @pending.delete(decision.case_id)
      return unless kase && letter && @teller

      clerk = @clerks[decision.from]
      reply, loan_id = if decision.approve && clerk
        @teller.lend_for(letter, actor: clerk.staff.actor)
      else
        [ @teller.reject_loan(letter, decision.reason), nil ]
      end
      kase.update!(status: loan_id ? "approved" : "rejected", decided_by: decision.from, reason: reply.ok ? decision.reason : reply.message,
                   loan_id:, decided_day: today, handled_by: kase.handled_by || decision.from)
      @board.letter(Board::TELLER, letter.from, reply)
      @board.debts if reply.ok
      letter.reply_to << reply
    rescue Ractor::ClosedError
      nil
    end

    # 係長に、督促状を出すローンを返す（返したものは、督促した日を書く）
    def overdue(ask)
      @board.letter(ask.from, Board::TELLER, ask)
      day = today
      # 住民ごとに1通（延滞しているローンの残りを合わせる）
      items = LoanCase.to_dun(day).select { it.outstanding.positive? }.group_by(&:resident).map do |resident, cases|
        cases.each { it.update!(last_dunned_day: day) }
        days = cases.map { day - (it.last_repaid_day || it.decided_day || it.day).to_i }.max
        Letters::OverdueItem.new(resident:, owed: cases.sum(&:outstanding), days:)
      end
      reply = Letters::Overdue.new(items: Ractor.make_shareable(items))
      @board.letter(Board::TELLER, ask.from, reply)
      ask.reply_to << reply
    rescue Ractor::ClosedError
      nil
    end

    # 郵便屋の写し。行員（たま）が係長へ回した申込なら、申込を「回した」にする（役場からたまへ届けた写しは数えない）
    def copied(copy)
      if copy.letter.is_a?(Letters::Case) && @clerks.key?(copy.from)
        LoanCase.where(id: copy.letter.id, status: "applied").update_all(status: "forwarded", handled_by: copy.from)
      end
      @board.letter(copy.from, copy.to, copy.letter)
    end

    def today = @teller&.today&.day || Control.current.day

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
