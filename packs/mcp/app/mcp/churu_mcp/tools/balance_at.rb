module ChuruMcp
  module Tools
    class BalanceAt < Base
      tool_name "balance_at"
      title "時点指定の残高"
      description <<~TEXT
        ある日の終わり時点の残高を、イベントから計算して返します。見方が2通りあり、両方を返します:
        - as_of（起算日基準）… 「本当はその日に何があったか」。あとから過去の日付で記帳した入出金も、その日に入る
        - as_at（記帳日基準）… 「その日の時点で銀行が知っていたこと」
        ふつうに「〇日の残高は？」と聞かれたら as_of を答えてください。2つが違うときは、あとから過去日付で記帳した取引があります。
      TEXT
      input_schema(
        properties: {
          account_number: ACCOUNT_NUMBER,
          date: DATE.merge(description: "日付（YYYY-MM-DD、その日の終わり時点）")
        },
        required: %w[account_number date]
      )
      annotations(**READ_ONLY)

      class << self
        private

        def run(account_number:, date:)
          find_account!(account_number)
          day = parse_date(date, "日付")
          { account_number:, date: day.iso8601,
            as_of: Banking::Statement.new(account_number, date: day, basis: :as_of).balance,
            as_at: Banking::Statement.new(account_number, date: day, basis: :as_at).balance }
        end
      end
    end
  end
end
