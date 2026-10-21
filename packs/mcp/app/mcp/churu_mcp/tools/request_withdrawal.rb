module ChuruMcp
  module Tools
    # 出金の依頼（窓口取引、TODO の Q1）。MCP から直接は出金できない: 依頼を出すだけで、行員が窓口（/admin/counter）で
    # 処理したときに口座から出金される。行員の操作（処理・断る）は MCP には出さない（MCP にはだれが使っているかの区別がないため）
    class RequestWithdrawal < Base
      tool_name "request_withdrawal"
      title "出金の依頼"
      description <<~TEXT
        口座からの出金を依頼します。お金はまだ動きません。銀行の行員が窓口で処理すると出金され、断られることもあります。
        凍結中・残高が足りないとエラーになります（ドライランでも同じ）。
        confirm を付けない（false の）ときはドライランで、何も書き込まずに「処理されたときの残高・警告・発生するイベント」を返します。
        利用者にドライランの結果を見せて OK をもらってから、同じ引数に confirm: true を付けて呼ぶと依頼を出します。
        処理されたかは get_account の通帳（「出金」の行が増える）で確かめられます。
      TEXT
      input_schema(
        properties: {
          account_number: ACCOUNT_NUMBER,
          amount: { type: "integer", minimum: 1, description: "金額（ちゅ〜る、1以上の整数）" },
          memo: { type: "string", maxLength: 100, description: "メモ（通帳に出る。例: おやつ代）" },
          confirm: CONFIRM
        },
        required: %w[account_number amount]
      )
      annotations(**WRITE, destructive_hint: false)

      class << self
        private

        def run(account_number:, amount:, memo: nil, confirm: false)
          outcome = bank.request_withdrawal(account_number, amount, memo:, dry_run: !confirm)
          result = outcome_to_h(outcome, confirm_hint: "口座 #{account_number} から #{amount} ちゅ〜るの出金を依頼します")
          outcome.dry_run? ? result : result.merge(request_id: outcome.request_id)
        end
      end
    end
  end
end
