module ChuruMcp
  module Tools
    class Transfer < Base
      tool_name "transfer"
      title "振込"
      description <<~TEXT
        口座から別の口座へ振り込みます。残高が足りないとエラーになります（ドライランでも同じ）。
        confirm を付けない（false の）ときはドライランで、何も書き込まずに「振込元の残高の変化・警告・発生するイベント」を返します。
        warnings があれば必ず利用者に伝えてください（例: 振込先が凍結中だと、入金できずに組戻しになります）。
        利用者の OK をもらってから、同じ引数に confirm: true を付けて呼ぶと受け付けます。
        受け付けた時点で振込元から引き落とされ、振込先への入金は少しあとに非同期で行われます。
        結果の transfer_id を get_transfer に渡すと、完了したか（組戻しになったか）を確かめられます。
      TEXT
      input_schema(
        properties: {
          from_account: ACCOUNT_NUMBER.merge(description: "振込元の口座番号（7桁）"),
          to_account: ACCOUNT_NUMBER.merge(description: "振込先の口座番号（7桁）"),
          amount: { type: "integer", minimum: 1, description: "金額（ちゅ〜る、1以上の整数）" },
          memo: { type: "string", maxLength: 100, description: "摘要（両方の通帳に出るメモ）" },
          confirm: CONFIRM
        },
        required: %w[from_account to_account amount]
      )
      annotations(**WRITE, destructive_hint: true)

      class << self
        private

        def run(from_account:, to_account:, amount:, memo: nil, confirm: false)
          outcome = bank.transfer(from_account, to_account, amount, memo:, dry_run: !confirm)
          result = outcome_to_h(outcome, confirm_hint: "口座 #{from_account} から #{to_account} へ #{amount} ちゅ〜る振り込みます")
          result.merge!(from_account:, to_account:)
          unless outcome.dry_run?
            result.merge!(transfer_id: outcome.transfer_id, status: "requested",
                          summary: "振込を受け付けました。振込先への入金は少しあとに行われます（get_transfer で確認）")
          end
          result
        end
      end
    end
  end
end
