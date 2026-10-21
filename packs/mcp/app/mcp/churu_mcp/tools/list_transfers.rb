module ChuruMcp
  module Tools
    class ListTransfers < Base
      tool_name "list_transfers"
      title "振込の一覧"
      description <<~TEXT
        振込を新しい順に limit 件返します。account_number を渡すと、その口座が振込元か振込先のものだけにします。
        status は scheduled（予約中: まだ引き落としていない。実行日は execute_on）/ held（保留中: 高額なので引き落とし済みで行員の確認待ち）/ requested（処理中: 引き落とし済みで入金待ち）/ completed（完了）/ failed（組戻し: 振込元に返金済み）/ unexecuted（実行できず: 実行日に残高不足など。お金は動いていない）/ cancelled（利用者が取消）/ stopped（行員が差し止め）/ reversed（完了後に組戻し）。
      TEXT
      input_schema(
        properties: {
          account_number: ACCOUNT_NUMBER,
          limit: { type: "integer", minimum: 1, maximum: 100, default: 10, description: "件数（新しいほうから）" }
        }
      )
      annotations(**READ_ONLY)

      class << self
        private

        def run(account_number: nil, limit: 10)
          transfers = ::Transfer.order(requested_at: :desc, id: :desc).limit(limit)
          transfers = transfers.involving(account_number) if account_number
          { transfers: transfers.map { |transfer| transfer_to_h(transfer) } }
        end
      end
    end
  end
end
