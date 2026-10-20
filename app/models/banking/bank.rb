# 口座を操作する唯一の入口。Web・MCP・コンソールはすべてここを通す。
#
#   bank = Banking::Bank.new(actor: "web")
#   bank.deposit("0000001", 100, memo: "おこづかい")
#   bank.withdraw("0000001", 30, dry_run: true)  # 書き込まずに結果だけ返す
#
# 書き込みは「集約を読み込む → ルールを確かめて apply → まとめて publish」。
# publish と同期プロジェクションは1つのトランザクションに入れるので、
# イベントだけ残って読み取りモデルが更新されない、ということは起きない。
module Banking
  class Bank
    # ドライランでも本番でも同じ形で返す
    Outcome = Data.define(:account_number, :events, :balance_before, :balance_after, :dry_run) do
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

    # 集約から組み立てた「いまの」口座（読み取りモデルを使わない）
    def load(number)
      @repository.load(Account.new(number), Account.stream_name(number))
    end

    private

    def change(number, dry_run:)
      stream = Account.stream_name(number)
      account = @repository.load(Account.new(number), stream)
      before = account.balance
      yield account
      events = account.unpublished_events.to_a

      unless dry_run
        ActiveRecord::Base.transaction do
          @event_store.with_metadata(actor: @actor) { @repository.store(account, stream) }
        end
      end

      Outcome.new(account_number: number, events:, balance_before: before,
                  balance_after: account.balance, dry_run:)
    rescue RubyEventStore::WrongExpectedEventVersion
      raise ConcurrentModification, "口座 #{number} が同時に更新されました。もう一度やり直してください"
    end

    def next_account_number
      format("%07d", ::Account.maximum(:number).to_i + 1)
    end
  end
end
