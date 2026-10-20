require "test_helper"

# /mcp に JSON-RPC を送って、MCP のやりとりを通しで確かめる
class ChuruMcp::ServerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    host! "localhost"
    bank = Banking::Bank.new(actor: "test")
    @alice = bank.open_account(holder_name: "オルカ").account_number
    @bob = bank.open_account(holder_name: "ミケ").account_number
    bank.deposit(@alice, 100, memo: "おこづかい")
  end

  def event_store = Rails.configuration.event_store

  def rpc(method, params = {}, headers: {}, env: {})
    @id = @id.to_i + 1
    post "/mcp", params: { jsonrpc: "2.0", id: @id, method:, params: }.to_json,
                 headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }
                   .merge(headers),
                 env: env
    response.parsed_body
  end

  def call_tool(name, arguments = {})
    rpc("tools/call", { name:, arguments: }).fetch("result")
  end

  test "initialize でサーバーの情報と使い方を返す" do
    body = rpc("initialize", { protocolVersion: "2025-11-25", capabilities: {},
                               clientInfo: { name: "test", version: "1.0" } })

    assert_response :success
    assert_equal "churu-bank", body.dig("result", "serverInfo", "name")
    assert_match "confirm: true", body.dig("result", "instructions")
  end

  test "tools/list でツールが並ぶ" do
    tools = rpc("tools/list").dig("result", "tools")

    assert_equal %w[list_accounts get_account balance_at list_transfers get_transfer deposit withdraw transfer],
                 tools.pluck("name")
    transfer = tools.find { |tool| tool["name"] == "transfer" }
    assert_equal false, transfer.dig("inputSchema", "properties", "confirm", "default")
    assert_equal true, tools.find { |tool| tool["name"] == "get_account" }.dig("annotations", "readOnlyHint")
  end

  test "読み取り: 口座一覧・残高と通帳・時点指定の残高" do
    accounts = call_tool("list_accounts").dig("structuredContent", "accounts")
    assert_equal [ [ @alice, 100 ], [ @bob, 0 ] ], accounts.map { |a| a.values_at("account_number", "balance") }

    account = call_tool("get_account", { account_number: @alice, limit: 5 })["structuredContent"]
    assert_equal 100, account["balance"]
    assert_equal [ [ "deposit", 100, "おこづかい" ] ], account["entries"].map { |e| e.values_at("kind", "amount", "memo") }

    at = call_tool("balance_at", { account_number: @alice, date: Date.current.iso8601 })["structuredContent"]
    assert_equal [ 100, 100 ], at.values_at("as_of", "as_at")
  end

  test "ドライラン（confirm なし）では何も書き込まれない" do
    before = event_store.read.count

    result = nil
    assert_no_enqueued_jobs { result = call_tool("transfer", { from_account: @alice, to_account: @bob, amount: 30 }) }

    content = result["structuredContent"]
    assert content["dry_run"]
    assert_equal [ 100, 70 ], content.values_at("balance_before", "balance_after")
    assert_equal %w[TransferDebited TransferRequested], content["events"].pluck("type")
    assert_nil content["transfer_id"]
    assert_equal before, event_store.read.count
    assert_equal 100, Account.find_by!(number: @alice).balance
  end

  test "confirm: true で書き込まれ、actor は mcp" do
    result = perform_enqueued_jobs do
      call_tool("transfer", { from_account: @alice, to_account: @bob, amount: 30, memo: "おやつ", confirm: true })
    end

    content = result["structuredContent"]
    assert_not content["dry_run"]
    assert_equal 70, Account.find_by!(number: @alice).balance
    assert_equal 30, Account.find_by!(number: @bob).balance
    assert_equal "mcp", event_store.read.stream("Account$#{@alice}").last.metadata[:actor]

    status = call_tool("get_transfer", { transfer_id: content["transfer_id"] })["structuredContent"]
    assert_equal "completed", status["status"]
    assert_equal [ content["transfer_id"] ],
                 call_tool("list_transfers", { account_number: @bob })["structuredContent"]["transfers"].pluck("transfer_id")
  end

  test "入金・出金もドライランが既定" do
    assert call_tool("deposit", { account_number: @bob, amount: 5 }).dig("structuredContent", "dry_run")
    assert call_tool("withdraw", { account_number: @alice, amount: 5 }).dig("structuredContent", "dry_run")
    assert_equal [ 100, 0 ], [ @alice, @bob ].map { |n| Account.find_by!(number: n).balance }

    call_tool("deposit", { account_number: @bob, amount: 5, confirm: true })
    call_tool("withdraw", { account_number: @alice, amount: 5, confirm: true })
    assert_equal [ 95, 5 ], [ @alice, @bob ].map { |n| Account.find_by!(number: n).balance }
  end

  test "業務エラーは isError のツール結果で、理由を返す" do
    result = call_tool("withdraw", { account_number: @alice, amount: 1000 })

    assert result["isError"]
    assert_match "残高不足", result.dig("content", 0, "text")
  end

  test "引数がスキーマに合わなければエラー" do
    result = call_tool("deposit", { account_number: @alice, amount: 0 })

    assert result["isError"]
    assert_equal 100, Account.find_by!(number: @alice).balance
  end

  test "localhost 以外からは 403" do
    rpc("tools/list", env: { "REMOTE_ADDR" => "192.168.1.10" })

    assert_response :forbidden
  end

  test "トークンを設定したら Bearer が必要" do
    ENV["CHURU_MCP_TOKEN"] = "secret-for-test"

    rpc("tools/list")
    assert_response :unauthorized
    rpc("tools/list", headers: { "Authorization" => "Bearer wrong" })
    assert_response :unauthorized
    rpc("tools/list", headers: { "Authorization" => "Bearer secret-for-test" })
    assert_response :success
  ensure
    ENV.delete("CHURU_MCP_TOKEN")
  end
end
