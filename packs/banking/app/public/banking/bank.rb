# 口座を操作する唯一の入口。Web・MCP・コンソールはすべてここを通す。
#
#   bank = Banking::Bank.new(actor: "web")
#   bank.deposit("0000001", 100, memo: "おこづかい")
#   bank.withdraw("0000001", 30, dry_run: true)  # 書き込まずに結果だけ返す
#   bank.transfer("0000001", "0000002", 50)      # 引き落としまで。入金は非同期
#   bank.transfer("0000001", "0000002", 50, execute_on: Date.tomorrow) # 予約振込（引き落としは実行日）
#   bank.cancel_transfer(transfer_id, from: "0000001") # 実行前（予約中・保留中）の取消（利用者）
#   bank.stop_transfer(transfer_id, reason: "詐欺の疑い") # 実行前の差し止め（行員）
#   bank.release_transfer(transfer_id)          # 高額で保留中の振込を通す（行員）
#   bank.reverse("0000001", event_id, reason: "金額まちがい")  # 入金・出金の取消
#   bank.reverse_transfer(transfer_id, reason: "振込先まちがい") # 完了した振込の組戻し
#   bank.pay_interest(date: Date.yesterday)      # 日次の利息（ふだんは Interest::PayJob が呼ぶ）
#
# 書き込みは「集約を読み込む → ルールを確かめて apply → まとめて publish」。
# publish と同期プロジェクションは1つのトランザクションに入れるので、
# イベントだけ残って読み取りモデルが更新されない、ということは起きない。
module Banking
  class Bank
    # ドライランでも本番でも同じ形で返す
    Outcome = Data.define(:account_number, :events, :balance_before, :balance_after, :dry_run,
                          :transfer_id, :warnings) do
      def initialize(transfer_id: nil, warnings: [], **) = super

      def dry_run? = dry_run
    end

    def initialize(actor:, event_store: Rails.configuration.event_store)
      @actor = actor
      @event_store = event_store
      @repository = AggregateRoot::Repository.new(event_store)
    end

    def open_account(holder_name:, dry_run: false)
      number = next_account_number
      change(number, dry_run:) { |account| account.open(holder_name:) }
    end

    def deposit(number, amount, memo: nil, value_date: nil, dry_run: false)
      change(number, dry_run:) { |account| account.deposit(amount, memo:, value_date:) }
    end

    def withdraw(number, amount, memo: nil, value_date: nil, dry_run: false)
      change(number, dry_run:) { |account| account.withdraw(amount, memo:, value_date:) }
    end

    # 入金・出金の取消（逆仕訳）。event_id は取り消す入金・出金のイベント（LedgerEntry#event_id）。
    # 元のイベントは残し、DepositReversed / WithdrawalReversed で相殺する。二重取消・取消の取消は不可。
    # 振込はここでは取り消せない（reverse_transfer で組戻しする）
    def reverse(number, event_id, reason:, dry_run: false)
      change(number, dry_run:) { |account| account.reverse(event_id, reason:) }
    end

    def freeze_account(number, reason:, dry_run: false)
      change(number, dry_run:) { |account| account.freeze!(reason:) }
    end

    def unfreeze_account(number, dry_run: false)
      change(number, dry_run:) { |account| account.unfreeze! }
    end

    def close_account(number, dry_run: false)
      change(number, dry_run:) { |account| account.close! }
    end

    # 振込の受付と引き落とし（同期）。振込先への入金は、TransferDebited のコミット後に
    # Transfers::SettleJob（Solid Queue）が settle_transfer を呼んで行う。
    #
    # - execute_on（明日以降の日付）を渡すと予約振込。受付だけして、引き落としは実行日（execute_transfer）
    # - 金額が保留のしきい値（Bank.hold_threshold）以上なら、引き落としたあと「保留中」にして、
    #   行員が release_transfer するまで入金しない。holdable: false（商店の支払い・返金）は保留しない
    def transfer(from, to, amount, memo: nil, execute_on: nil, holdable: true, dry_run: false)
      transfer_id = SecureRandom.uuid
      source = load_account(from)
      destination = load_account(to)
      raise NotFound, "振込先の口座 #{to} はありません" if destination.status == :unopened

      warnings = []
      unless destination.status == :active
        warnings << "振込先の口座は#{status_label(destination.status)}なので、入金できずに組戻しになります"
      end
      return schedule_transfer(transfer_id, source, to, amount, memo:, execute_on:, holdable:, warnings:, dry_run:) if execute_on

      before = source.balance
      source.debit_for_transfer(transfer_id:, amount:, to:, memo:)
      transfer = Transfer.new(transfer_id)
      transfer.request(from:, to:, amount:, memo:)
      if holdable && held_amount?(amount)
        transfer.hold!(threshold: self.class.hold_threshold)
        warnings << hold_warning
      end

      events = source.unpublished_events.to_a + transfer.unpublished_events.to_a
      unless dry_run
        store_all(source => Account.stream_name(from), transfer => Transfer.stream_name(transfer_id)) do
          link_to_transfer(transfer_id, events.first)
        end
      end

      Outcome.new(account_number: from, events:, balance_before: before, balance_after: source.balance,
                  dry_run:, transfer_id:, warnings:)
    end

    # 予約振込の実行（Transfers::ExecuteDueJob が execute_due_transfers から呼ぶ）。実行日が来ていれば
    # 振込元から引き落として「処理中」（高額なら「保留中」）にする。このあとはふつうの振込と同じ。
    # 残高不足・凍結などで引き落とせなければ「実行できず」（お金は動かない）。
    # 予約中でない・実行日前なら何もしない（nil）ので、何度呼ばれても1回分しか動かない。
    # 同じ振込を利用者が同時に取り消していたら、Transfer$ の expected_version で負けて ConcurrentModification
    def execute_transfer(transfer_id, date: Date.current)
      transfer = load_transfer(transfer_id)
      return unless transfer.scheduled? && transfer.execute_on <= date

      source = load_account(transfer.from_account)
      begin
        source.debit_for_transfer(transfer_id:, amount: transfer.amount, to: transfer.to_account, memo: transfer.memo)
      rescue Banking::Error, ArgumentError => e
        transfer.fail_scheduled!(reason: e.message)
        store_all(transfer => Transfer.stream_name(transfer_id))
        return transfer
      end

      transfer.start!
      transfer.hold!(threshold: self.class.hold_threshold) if transfer.holdable? && held_amount?(transfer.amount)
      debited = source.unpublished_events.first
      store_all(source => Account.stream_name(transfer.from_account), transfer => Transfer.stream_name(transfer_id)) do
        link_to_transfer(transfer_id, debited)
      end
      transfer
    end

    # 実行日が date 以前の予約振込をすべて実行する。実行した（または実行できなかった）振込の集約を返す。
    # 1件が同時更新で負けても（ちょうど取り消された等）ほかは続ける。負けた振込は次の回にまた見る
    def execute_due_transfers(date: Date.current)
      ::Transfer.where(status: "scheduled", execute_on: ..date).order(:execute_on, :id).pluck(:transfer_id)
                .filter_map do |transfer_id|
        execute_transfer(transfer_id, date:)
      rescue ConcurrentModification
        nil
      end
    end

    # 保留中の振込を行員が通す。このあと Transfers::SettleJob が入金する。Outcome は振込先の口座
    # （残高はまだ変わらない。入金されると balance_after の額になる）
    def release_transfer(transfer_id, dry_run: false)
      transfer = load_existing_transfer(transfer_id)
      transfer.release!
      destination = load_account(transfer.to_account)
      warnings = []
      unless destination.status == :active
        warnings << "振込先の口座は#{status_label(destination.status)}なので、入金できずに組戻しになります"
      end

      events = transfer.unpublished_events.to_a
      store_all(transfer => Transfer.stream_name(transfer_id)) unless dry_run
      Outcome.new(account_number: transfer.to_account, events:, balance_before: destination.balance,
                  balance_after: destination.balance + transfer.amount, dry_run:, transfer_id:, warnings:)
    end

    # 実行前（予約中・保留中）の振込を、利用者が取り消す。from を渡すと、その口座からの振込でなければ NotFound
    # （画面は自分の口座番号を渡す）。引き落とし済み（保留中）なら振込元へ払い戻す。Outcome は振込元の口座
    def cancel_transfer(transfer_id, from: nil, reason: "利用者が取り消しました", dry_run: false)
      halt_transfer(transfer_id, from:, dry_run:) { |transfer| transfer.cancel!(reason:) }
    end

    # 実行前（予約中・保留中）の振込を、行員が差し止める。理由は必須。引き落とし済みなら振込元へ払い戻す
    def stop_transfer(transfer_id, reason:, dry_run: false)
      halt_transfer(transfer_id, dry_run:) { |transfer| transfer.stop!(reason:) }
    end

    # 振込の後半（入金 → 完了、入金できなければ組戻し → 失敗）。何度呼ばれても1回分しか動かない
    def settle_transfer(transfer_id)
      transfer = load_transfer(transfer_id)
      return unless transfer.requested?

      destination = load_account(transfer.to_account)
      begin
        destination.credit_transfer(transfer_id:, amount: transfer.amount, from: transfer.from_account,
                                    memo: transfer.memo)
        transfer.complete!
        account, number = destination, transfer.to_account
      rescue Banking::Error => e
        source = load_account(transfer.from_account)
        source.refund_transfer(transfer_id:, amount: transfer.amount, to: transfer.to_account, reason: e.message)
        transfer.fail!(reason: e.message)
        account, number = source, transfer.from_account
      end

      money_event = account.unpublished_events.first
      store_all(account => Account.stream_name(number), transfer => Transfer.stream_name(transfer_id)) do
        link_to_transfer(transfer_id, money_event)
      end
      transfer
    end

    # 完了した振込の組戻し（取消）。1つのトランザクションで
    #   Account$<振込先> TransferCreditReversed（引き戻し）→ Account$<振込元> TransferRefunded（払い戻し）
    #   → Transfer$<id> TransferReversed
    # を書く。振込先の残高が足りなければ InsufficientFunds。処理中・失敗（組戻し済み）の振込は不可。
    # 返す Outcome は振込元の口座のもの
    def reverse_transfer(transfer_id, reason:, dry_run: false)
      transfer = load_existing_transfer(transfer_id)
      transfer.reverse!(reason:)
      from, to = transfer.from_account, transfer.to_account
      destination = load_account(to)
      source = load_account(from)
      raise InvalidState, "振込元の口座 #{from} は解約済みなので組戻しできません" if source.status == :closed

      before = source.balance
      destination.reverse_transfer_credit(transfer_id:, amount: transfer.amount, from:, reason:)
      source.refund_transfer(transfer_id:, amount: transfer.amount, to:, reason:)

      money_events = destination.unpublished_events.to_a + source.unpublished_events.to_a
      events = money_events + transfer.unpublished_events.to_a
      unless dry_run
        store_all(destination => Account.stream_name(to), source => Account.stream_name(from),
                  transfer => Transfer.stream_name(transfer_id)) do
          money_events.each { |event| link_to_transfer(transfer_id, event) }
        end
      end

      Outcome.new(account_number: from, events:, balance_before: before, balance_after: source.balance,
                  dry_run:, transfer_id:)
    end

    # 日次の利息（Interest::PayJob が毎日、前日分を呼ぶ）。全口座に pay_interest_to して、
    # 利息のイベントを書いた口座の Outcome を返す。何度呼んでも同じ日の利息は1回だけ
    def pay_interest(date: Date.yesterday, annual_rate: self.class.annual_interest_rate, dry_run: false)
      opened = @event_store.read.of_type(Events::AccountOpened).map { |event| event.data.fetch(:account_number) }
      opened.filter_map { |number| pay_interest_to(number, date:, annual_rate:, dry_run:) }
    end

    # 1口座分の利息。date の日の終わりの残高（起算日基準 = Statement の as_of）に年利 ÷ 365 をかける。
    # 支払い済み・解約済み・残高 0 なら何もせず nil（端数の扱いは Banking::Account#pay_interest）
    def pay_interest_to(number, date: Date.yesterday, annual_rate: self.class.annual_interest_rate,
                        dry_run: false)
      account = load_account(number)
      return if %i[unopened closed].include?(account.status) || account.interest_paid_on?(date)

      base_balance = Statement.new(number, date:, event_store: @event_store).balance
      outcome = change(number, dry_run:, account:) do |a|
        a.pay_interest(date:, base_balance:, annual_rate:)
      end
      outcome unless outcome.events.empty?
    end

    # 年利（文字列の小数。例: "0.365"）。packs/banking/config/initializers/banking_interest.rb で設定
    def self.annual_interest_rate = Rails.configuration.x.banking.annual_interest_rate

    # 振込の保留のしきい値（ちゅ〜る）。この額以上の振込は行員が通すまで入金しない。
    # packs/banking/config/initializers/banking_transfers.rb で設定
    def self.hold_threshold = Integer(Rails.configuration.x.banking.transfer_hold_threshold)

    # 予約振込の実行日は、明日から何日先まで選べるか
    MAX_SCHEDULE_DAYS = 365

    # 集約から組み立てた「いまの」口座（読み取りモデルを使わない）
    def load_account(number)
      @repository.load(Account.new(number), Account.stream_name(number))
    end

    private

    def load_transfer(transfer_id) = @repository.load(Transfer.new(transfer_id), Transfer.stream_name(transfer_id))

    def load_existing_transfer(transfer_id)
      load_transfer(transfer_id).tap do |transfer|
        raise NotFound, "振込 #{transfer_id} はありません" if transfer.status == :new
      end
    end

    def held_amount?(amount) = amount.is_a?(Integer) && amount >= self.class.hold_threshold

    def hold_warning
      "#{self.class.hold_threshold} ちゅ〜る以上の振込なので、引き落としたあと行員が確認するまで「保留中」になります" \
        "（入金は確認のあと。保留のあいだは取り消せます）"
    end

    # 予約振込の受付。引き落とさないので残高は変わらない（足りなければ警告だけ）
    def schedule_transfer(transfer_id, source, to, amount, memo:, execute_on:, holdable:, warnings:, dry_run:)
      execute_on = validate_execute_on(execute_on)
      source.ensure_can_transfer!(amount:, to:)
      transfer = Transfer.new(transfer_id)
      transfer.schedule(from: source.number, to:, amount:, memo:, execute_on:, holdable:)

      warnings.unshift("#{execute_on.strftime('%-m/%-d')} に引き落として振り込みます。いまはまだ引き落としません")
      if amount > source.balance
        warnings << "いまの残高（#{source.balance} ちゅ〜る）では足りません。実行日までに入金がないと振り込まれません"
      end
      warnings << hold_warning.sub("引き落としたあと", "実行日に引き落としたあと") if holdable && held_amount?(amount)

      events = transfer.unpublished_events.to_a
      store_all(transfer => Transfer.stream_name(transfer_id)) unless dry_run
      Outcome.new(account_number: source.number, events:, balance_before: source.balance,
                  balance_after: source.balance, dry_run:, transfer_id:, warnings:)
    end

    def validate_execute_on(value)
      date = value.is_a?(Date) ? value : Date.iso8601(value.to_s)
      raise ArgumentError, "実行日は明日以降の日付を入れてください（今日なら空のままにします）" unless date > Date.current
      if date > Date.current + MAX_SCHEDULE_DAYS
        raise ArgumentError, "実行日は #{MAX_SCHEDULE_DAYS} 日先までです"
      end

      date
    rescue Date::Error
      raise ArgumentError, "実行日は YYYY-MM-DD で入れてください（#{value}）"
    end

    # 実行前の振込の取消・差し止め（どちらにするかはブロックで集約のメソッドを呼ぶ）。
    # 状態の確認（実行が始まっていたら InvalidState）を先にして、引き落とし済みなら払い戻す
    def halt_transfer(transfer_id, from: nil, dry_run:)
      transfer = load_existing_transfer(transfer_id)
      raise NotFound, "振込 #{transfer_id} はありません" if from && transfer.from_account != from

      yield transfer
      reason = transfer.unpublished_events.to_a.last.data.fetch(:reason)
      source = load_account(transfer.from_account)
      before = source.balance
      if transfer.debited?
        source.refund_transfer(transfer_id:, amount: transfer.amount, to: transfer.to_account, reason:)
      end

      money_events = source.unpublished_events.to_a
      events = money_events + transfer.unpublished_events.to_a
      unless dry_run
        aggregates = money_events.any? ? { source => Account.stream_name(transfer.from_account) } : {}
        aggregates[transfer] = Transfer.stream_name(transfer_id)
        store_all(aggregates) { money_events.each { |event| link_to_transfer(transfer_id, event) } }
      end

      Outcome.new(account_number: transfer.from_account, events:, balance_before: before,
                  balance_after: source.balance, dry_run:, transfer_id:)
    end

    def change(number, dry_run:, account: load_account(number))
      before = account.balance
      yield account
      events = account.unpublished_events.to_a
      store_all(account => Account.stream_name(number)) unless dry_run

      Outcome.new(account_number: number, events:, balance_before: before,
                  balance_after: account.balance, dry_run:)
    end

    # 複数の集約を1つのトランザクションで保存する。どれかが同時更新で負けたら全部取り消し
    def store_all(aggregates_with_streams)
      ActiveRecord::Base.transaction do
        @event_store.with_metadata(actor: @actor) do
          aggregates_with_streams.each { |aggregate, stream| @repository.store(aggregate, stream) }
          yield if block_given?
        end
      end
    rescue RubyEventStore::WrongExpectedEventVersion
      raise ConcurrentModification, "口座が同時に更新されました。もう一度やり直してください"
    end

    # 口座側のお金の動き（引き落とし・入金・組戻し）も Transfer$<id> から辿れるようにする
    def link_to_transfer(transfer_id, event)
      @event_store.link(event.event_id, stream_name: Transfer.stream_name(transfer_id))
    end

    def status_label(status) = ::Account::STATUS_LABELS.fetch(status.to_s, status.to_s)

    def next_account_number
      format("%07d", ::Account.maximum(:number).to_i + 1)
    end
  end
end
