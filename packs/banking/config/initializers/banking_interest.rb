# 利息の年利（文字列の小数）。日割りは年利 ÷ 365。
# 既定は 36.5%（= 1日 0.1%）。銀行ごっこなので、少ない残高でも利息がつくのが見えるように高め。
# 環境変数 CHURU_ANNUAL_INTEREST_RATE で変えられる（例: "0.001"）
Rails.configuration.x.banking.annual_interest_rate = ENV.fetch("CHURU_ANNUAL_INTEREST_RATE", "0.365")
