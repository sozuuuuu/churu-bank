# 口座を操作する唯一の入口。Web・MCP・コンソールはすべてここを通す。
#
#   bank = Banking::Bank.new(actor: "web")
#   bank.deposit("0000001", 100, memo: "おこづかい")
#   bank.withdraw("0000001", 30, dry_run: true)  # 書き込まずに結果だけ返す
#   bank.transfer("0000001", "0000002", 50)      # 引き落としまで。入金は非同期
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
    def transfer(from, to, amount, memo: nil, dry_run: false)
      transfer_id = SecureRandom.uuid
      source = load(from)
      destination = load(to)
      raise NotFound, "振込先の口座 #{to} はありません" if destination.status == :unopened

      before = source.balance
      source.debit_for_transfer(transfer_id:, amount:, to:, memo:)
      transfer = Transfer.new(transfer_id)
      transfer.request(from:, to:, amount:, memo:)

      warnings = []
      unless destination.status == :active
        warnings << "振込先の口座は#{status_label(destination.status)}なので、入金できずに組戻しになります"
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

    # 振込の後半（入金 → 完了、入金できなければ組戻し → 失敗）。何度呼ばれても1回分しか動かない
    def settle_transfer(transfer_id)
      transfer = @repository.load(Transfer.new(transfer_id), Transfer.stream_name(transfer_id))
      return unless transfer.requested?

      destination = load(transfer.to_account)
      begin
        destination.credit_transfer(transfer_id:, amount: transfer.amount, from: transfer.from_account,
                                    memo: transfer.memo)
        transfer.complete!
        account, number = destination, transfer.to_account
      rescue Banking::Error => e
        source = load(transfer.from_account)
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

    # 集約から組み立てた「いまの」口座（読み取りモデルを使わない）
    def load(number)
      @repository.load(Account.new(number), Account.stream_name(number))
    end

    private

    def change(number, dry_run:)
      account = load(number)
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
