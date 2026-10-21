# ツールを並べた MCP::Server を組み立てる（リクエストごとに1つ）
module ChuruMcp
  module Server
    TOOLS = [
      Tools::ListAccounts, Tools::GetAccount, Tools::BalanceAt, Tools::ListTransfers, Tools::GetTransfer,
      Tools::Deposit, Tools::RequestWithdrawal, Tools::Transfer
    ].freeze

    INSTRUCTIONS = <<~TEXT.freeze
      ちゅーる銀行（通貨「ちゅ〜る」、金額はすべて整数）の MCP サーバーです。
      書き込みのツール（deposit / request_withdrawal / transfer）は、confirm を付けないとドライラン（何も書き込まない試算）になります。
      必ず、まずドライランの結果（残高の変化・警告）を利用者に見せて OK をもらい、そのあと同じ引数に confirm: true を付けて実行してください。
      振込は受け付けた時点で振込元から引き落とされ、振込先への入金は少しあとに非同期で行われます。状態は get_transfer で確かめられます。
      transfer に execute_on を渡すと予約振込（実行日に引き落とし）。高額の振込は行員が確認するまで保留になります。
      出金は request_withdrawal で「依頼」を出すだけです。行員が窓口で処理すると出金されます（断られることもあります）。
    TEXT

    def self.build
      MCP::Server.new(
        name: "churu-bank",
        title: "ちゅーる銀行",
        version: "0.1.0",
        instructions: INSTRUCTIONS,
        tools: TOOLS,
        capabilities: { tools: {} }, # ツールだけ（プロンプト・リソースはない）
        configuration: MCP::Configuration.new(
          exception_reporter: ->(error, context) { Rails.error.report(error, context:, source: "churu_mcp") }
        )
      )
    end
  end
end
