# /mcp（Streamable HTTP）。SDK の Rails 向けの書き方に合わせて、リクエストごとに
# サーバーとトランスポートを作る（stateless・JSON で返す。セッションも SSE も持たない）。
#
# 外には公開しない前提だが、念のため:
#   - localhost 以外から来たリクエストは 403
#   - トークン（環境変数 CHURU_MCP_TOKEN か credentials の mcp.token）を設定したら、
#     Authorization: Bearer <トークン> がないと 401
# Host / Origin の検査（DNS リバインディング対策）は SDK のトランスポートが行う
module ChuruMcp
  class ServerController < ActionController::API
    before_action :require_local_request
    before_action :require_token

    def handle
      transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        Server.build, stateless: true, enable_json_response: true, serve_subscriptions_listen: false
      )
      status, headers, body = transport.handle_request(request)

      response.headers.merge!(headers.except("content-type"))
      if body.blank?
        head status
      else
        render plain: body.join, status:, content_type: headers.fetch("content-type", "application/json")
      end
    end

    def self.token
      ENV["CHURU_MCP_TOKEN"].presence || Rails.application.credentials.dig(:mcp, :token)
    end

    private

    def require_local_request
      head :forbidden unless request.local?
    end

    def require_token
      expected = self.class.token
      return if expected.blank?

      given = request.authorization.to_s.delete_prefix("Bearer ")
      head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(given, expected)
    end
  end
end
