module ChuruMcp
  module Tools
    class ListAccounts < Base
      tool_name "list_accounts"
      title "口座一覧"
      description <<~TEXT
        ちゅーる銀行の口座を一覧します（口座番号・名義・状態・いまの残高）。
        名義から口座番号を調べるときにも使います。解約済みの口座は include_closed: true のときだけ含めます。
      TEXT
      input_schema(
        properties: {
          include_closed: { type: "boolean", default: false, description: "解約済みの口座も含める" }
        }
      )
      annotations(**READ_ONLY)

      class << self
        private

        def run(include_closed: false)
          accounts = ::Account.order(:number)
          accounts = accounts.where.not(status: "closed") unless include_closed
          { accounts: accounts.map { |account| account_to_h(account) } }
        end
      end
    end
  end
end
