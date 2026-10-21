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
        execute_on（明日以降の日付）を渡すと予約振込になり、その日に引き落として振り込みます（それまでは引き落としません）。
        金額が大きいと「保留中」になり、銀行の行員が確認するまで入金されません（warnings に出ます）。
        予約中・保留中の振込は、利用者が画面から取り消せます。
        結果の transfer_id を get_transfer に渡すと、完了したか（組戻しになったか）を確かめられます。
      TEXT
      input_schema(
        properties: {
          from_account: ACCOUNT_NUMBER.merge(description: "振込元の口座番号（7桁）"),
          to_account: ACCOUNT_NUMBER.merge(description: "振込先の口座番号（7桁）"),
          amount: { type: "integer", minimum: 1, description: "金額（ちゅ〜る、1以上の整数）" },
          memo: { type: "string", maxLength: 100, description: "摘要（両方の通帳に出るメモ）" },
          execute_on: DATE.merge(description: "予約振込の実行日（YYYY-MM-DD、明日以降）。省略するとすぐ振り込む"),
          confirm: CONFIRM
        },
        required: %w[from_account to_account amount]
      )
      annotations(**WRITE, destructive_hint: true)

      # 受け付けたあとの状態ごとの説明
      SUMMARIES = {
        "scheduled" => "振込を予約しました。実行日に引き落として振り込みます（get_transfer で確認）",
        "held" => "振込を受け付けました。金額が大きいので保留中で、行員が確認してから入金されます（get_transfer で確認）",
        "requested" => "振込を受け付けました。振込先への入金は少しあとに行われます（get_transfer で確認）"
      }.freeze

      class << self
        private

        def run(from_account:, to_account:, amount:, memo: nil, execute_on: nil, confirm: false)
          execute_on = parse_date(execute_on, "実行日")
          outcome = bank.transfer(from_account, to_account, amount, memo:, execute_on:, dry_run: !confirm)
          hint = "口座 #{from_account} から #{to_account} へ #{amount} ちゅ〜る#{"、#{execute_on.iso8601} に" if execute_on}振り込みます"
          result = outcome_to_h(outcome, confirm_hint: hint)
          result.merge!(from_account:, to_account:, execute_on: execute_on&.iso8601).compact!
          unless outcome.dry_run?
            status = ::Transfer.find_by!(transfer_id: outcome.transfer_id).status
            result.merge!(transfer_id: outcome.transfer_id, status:, summary: SUMMARIES.fetch(status, SUMMARIES["requested"]))
          end
          result
        end
      end
    end
  end
end
