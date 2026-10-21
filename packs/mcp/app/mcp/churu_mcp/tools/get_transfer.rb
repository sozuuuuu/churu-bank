module ChuruMcp
  module Tools
    class GetTransfer < Base
      tool_name "get_transfer"
      title "振込の状態"
      description <<~TEXT
        振込 ID（transfer を confirm: true で実行したときに返る transfer_id）から、振込の状態を返します。
        status は scheduled（予約中: まだ引き落としていない。実行日は execute_on）/ held（保留中: 高額なので引き落とし済みで行員の確認待ち）/ requested（処理中: 引き落とし済みで入金待ち）/ completed（完了）/ failed（組戻し: 振込元に返金済み）/ unexecuted（実行できず: 実行日に残高不足など。お金は動いていない）/ cancelled（利用者が取消）/ stopped（行員が差し止め）/ reversed（完了後に組戻し）。
        理由は failure_reason（組戻し・実行できず）/ cancel_reason（取消・差し止め）。
        受け付けた直後は requested のことがあります。少し待ってからもう一度確かめてください。
      TEXT
      input_schema(
        properties: {
          transfer_id: { type: "string", description: "振込 ID（UUID）" }
        },
        required: %w[transfer_id]
      )
      annotations(**READ_ONLY)

      class << self
        private

        def run(transfer_id:)
          transfer = ::Transfer.find_by(transfer_id:)
          raise Banking::NotFound, "振込 #{transfer_id} はありません" unless transfer

          transfer_to_h(transfer)
        end
      end
    end
  end
end
