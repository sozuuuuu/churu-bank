# ちゅーる銀行の業務ロジック（イベントソーシング側）の名前空間。
# 画面や MCP は Banking::Bank を通してだけ口座を操作する。
module Banking
  class Error < StandardError; end

  class NotFound < Error; end
  class AlreadyOpened < Error; end
  class InvalidState < Error; end
  class InsufficientFunds < Error; end

  # 同じ口座に同時に書き込もうとして、後から来た方が負けたとき
  class ConcurrentModification < Error; end
end
