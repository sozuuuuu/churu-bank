# 振込の保留のしきい値（ちゅ〜る）。この額以上の振込は「保留中」になり、行員が通すまで入金しない。
# 既定は 300（シードの利用者が少し大きめの振込をすると保留になるくらい）。
# 環境変数 CHURU_TRANSFER_HOLD_THRESHOLD で変えられる。商店の支払い・返金は対象外
Rails.configuration.x.banking.transfer_hold_threshold = ENV.fetch("CHURU_TRANSFER_HOLD_THRESHOLD", "300")
