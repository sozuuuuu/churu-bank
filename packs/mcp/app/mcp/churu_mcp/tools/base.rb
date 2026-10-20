# ツールの共通部分。結果は structuredContent（JSON）と、同じ中身のテキストの両方で返す。
# 銀行の業務エラー（残高不足・凍結中など）は isError: true のツール結果にして、理由をそのまま伝える
module ChuruMcp
  module Tools
    class Base < MCP::Tool
      ACTOR = "mcp".freeze

      READ_ONLY = { read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false }.freeze
      WRITE = { read_only_hint: false, idempotent_hint: false, open_world_hint: false }.freeze

      ACCOUNT_NUMBER = { type: "string", pattern: "^[0-9]{7}$", description: "口座番号（7桁、例: 0000001）" }.freeze
      DATE = { type: "string", pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" }.freeze
      CONFIRM = {
        type: "boolean", default: false,
        description: "true のときだけ実際に書き込む。省略（false）だとドライラン。利用者の OK をもらってから true にする"
      }.freeze

      class << self
        def call(server_context:, **arguments)
          respond(run(**arguments))
        rescue Banking::Error, ArgumentError => e
          MCP::Tool::Response.new([ { type: "text", text: e.message } ], error: true)
        end

        private

        def respond(result)
          MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(result) } ], structured_content: result)
        end

        def bank = Banking::Bank.new(actor: ACTOR)

        def find_account!(number)
          ::Account.find_by(number:) || raise(Banking::NotFound, "口座 #{number} はありません")
        end

        def parse_date(value, name)
          return if value.blank?

          Date.iso8601(value)
        rescue Date::Error
          raise ArgumentError, "#{name}は YYYY-MM-DD で入れてください（#{value}）"
        end

        def account_to_h(account)
          { account_number: account.number, holder_name: account.holder_name, status: account.status,
            status_label: account.status_label, balance: account.balance, opened_on: account.opened_on.iso8601 }
        end

        def entry_to_h(entry)
          { booked_at: entry.booked_at.iso8601, value_date: entry.value_date.iso8601, kind: entry.kind,
            kind_label: entry.kind_label, amount: entry.amount, balance_after: entry.balance_after,
            memo: entry.memo, counterparty: entry.counterparty, transfer_id: entry.transfer_id,
            actor: entry.actor }.compact
        end

        def transfer_to_h(transfer)
          { transfer_id: transfer.transfer_id, from_account: transfer.from_account, to_account: transfer.to_account,
            amount: transfer.amount, memo: transfer.memo, status: transfer.status, status_label: transfer.status_label,
            failure_reason: transfer.failure_reason, requested_at: transfer.requested_at.iso8601,
            settled_at: transfer.settled_at&.iso8601, actor: transfer.actor }.compact
        end

        # 書き込みツールの結果。ドライランなら「何が起きるか」、確定なら「何が起きたか」
        def outcome_to_h(outcome, confirm_hint:)
          result = {
            dry_run: outcome.dry_run?,
            account_number: outcome.account_number,
            balance_before: outcome.balance_before,
            balance_after: outcome.balance_after,
            warnings: outcome.warnings,
            events: outcome.events.map { |event| { type: event.event_type.demodulize, data: event.data } }
          }
          if outcome.dry_run?
            result[:summary] = "ドライランです（まだ何も書き込んでいません）。#{confirm_hint}"
            result[:next_step] = "利用者の OK をもらったら、同じ引数に confirm: true を付けてもう一度呼んでください"
          else
            result[:summary] = "実行しました。#{confirm_hint.sub(/ます\z/, "ました")}"
          end
          result
        end
      end
    end
  end
end
