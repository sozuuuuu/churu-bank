module ChuruMcp
  module Tools
    class Deposit < Base
      tool_name "deposit"
      title "入金"
      description <<~TEXT
        口座に入金します。confirm を付けない（false の）ときはドライランで、何も書き込まずに
        「入金前後の残高・警告・発生するイベント」を返します。
        利用者にドライランの結果を見せて OK をもらってから、同じ引数に confirm: true を付けて呼ぶと実際に入金します。
      TEXT
      input_schema(
        properties: {
          account_number: ACCOUNT_NUMBER,
          amount: { type: "integer", minimum: 1, description: "金額（ちゅ〜る、1以上の整数）" },
          memo: { type: "string", maxLength: 100, description: "摘要（通帳に出るメモ。例: おこづかい）" },
          value_date: DATE.merge(description: "起算日（YYYY-MM-DD）。過去の日付の取引をあとから記帳するときだけ。省略すると今日"),
          confirm: CONFIRM
        },
        required: %w[account_number amount]
      )
      annotations(**WRITE, destructive_hint: false)

      class << self
        private

        def run(account_number:, amount:, memo: nil, value_date: nil, confirm: false)
          outcome = bank.deposit(account_number, amount, memo:, value_date: parse_date(value_date, "起算日"),
                                                         dry_run: !confirm)
          outcome_to_h(outcome, confirm_hint: "口座 #{account_number} に #{amount} ちゅ〜る入金します")
        end
      end
    end
  end
end
