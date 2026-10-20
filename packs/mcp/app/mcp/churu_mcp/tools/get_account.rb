module ChuruMcp
  module Tools
    class GetAccount < Base
      tool_name "get_account"
      title "残高と通帳"
      description <<~TEXT
        1つの口座のいまの残高と、通帳（入出金・振込の明細）の新しいほうから limit 件を返します。
        明細は古い順に並べ、各行に記帳日時（booked_at）・起算日（value_date）・金額（入金は正、出金は負）・その行のあとの残高を付けます。
        過去のある日の残高を知りたいときは balance_at を使ってください。
      TEXT
      input_schema(
        properties: {
          account_number: ACCOUNT_NUMBER,
          limit: { type: "integer", minimum: 1, maximum: 100, default: 10, description: "通帳の件数（新しいほうから）" }
        },
        required: %w[account_number]
      )
      annotations(**READ_ONLY)

      class << self
        private

        def run(account_number:, limit: 10)
          account = find_account!(account_number)
          entries = account.ledger_entries.reorder(booked_at: :desc, id: :desc).limit(limit).reverse
          account_to_h(account).merge(entries: entries.map { |entry| entry_to_h(entry) })
        end
      end
    end
  end
end
