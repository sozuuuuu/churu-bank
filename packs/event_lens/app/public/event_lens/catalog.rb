# イベントの日本語の名前・出来事の種類（色）・線画のアイコン・ひとこと説明と、中身（data / metadata）の項目名。
# 新しいイベントを足したら、ここにも1行足す（足し忘れは catalog_test が見つける）
module EventLens
  module Catalog
    # 出来事の種類。色は CSS の .kind-<key>、アイコンは Ui::ThemeHelper::ICONS
    Kind = Data.define(:key, :label, :icon)
    KINDS = [
      Kind.new(:money_in, "入金", :arrow_in),
      Kind.new(:money_out, "出金", :arrow_out),
      Kind.new(:transfer, "振込の手続き", :send),
      Kind.new(:guard, "止める・通す", :lock),
      Kind.new(:request, "依頼と承認", :letter),
      Kind.new(:shop, "商店", :bag),
      Kind.new(:account, "口座", :passbook),
      Kind.new(:loan, "ちゅ〜るローン", :key)
    ].index_by(&:key).freeze
    OTHER = Kind.new(:other, "そのほか", :alert)

    # type はイベントのクラス名（RES の event_type）
    Entry = Data.define(:type, :label, :kind, :icon, :description) do
      def kind_label = (KINDS[kind] || OTHER).label
    end

    B = Banking::Events
    S = Shop::Events
    A = Approvals::Events

    # [イベント, 日本語の名前, 種類, アイコン（nil なら種類のアイコン）, ひとこと説明]
    ROWS = [
      # ---- 口座（Account$<口座番号>） ----
      [ B::AccountOpened, "口座の開設", :account, nil, "新しい口座ができた" ],
      [ B::AccountClosed, "口座の解約", :account, :close, "口座をとじた" ],
      [ B::MoneyDeposited, "入金", :money_in, nil, "窓口でちゅ〜るを預かった" ],
      [ B::MoneyWithdrawn, "出金（窓口）", :money_out, nil, "出金依頼にこたえて、窓口でちゅ〜るを渡した" ],
      [ B::AccountFrozen, "口座の凍結", :guard, nil, "不正の疑いなどで、口座のお金を動かせなくした" ],
      [ B::AccountUnfrozen, "凍結の解除", :guard, :key, "凍結を外して、また使えるようにした（二人承認）" ],
      [ B::TransferDebited, "振込の引き落とし", :money_out, :send, "振込元の口座からお金を引いた" ],
      [ B::TransferCredited, "振込の入金", :money_in, nil, "振込先の口座にお金が入った" ],
      [ B::TransferRefunded, "振込の払い戻し", :money_in, :undo, "振り込めなかった・取り消したお金を、振込元へ戻した" ],
      [ B::TransferCreditReversed, "振込の入金の引き戻し", :money_out, :undo, "組戻しのため、振込先から入金を引き戻した" ],
      [ B::DepositReversed, "入金の取消", :money_out, :undo, "まちがえた入金を、逆向きの出来事で打ち消した（二人承認）" ],
      [ B::WithdrawalReversed, "出金の取消", :money_in, :undo, "まちがえた出金を、逆向きの出来事で打ち消した（二人承認）" ],
      [ B::InterestPaid, "利息", :money_in, :sprout, "前の日の残高に、1日分の利息がついた" ],
      [ B::LoanDisbursed, "借入の入金", :money_in, :key, "ちゅ〜るローンで借りたお金が口座に入った" ],
      [ B::LoanRepaymentDebited, "返済の引き落とし", :money_out, :key, "ちゅ〜るローンの返済で、口座からお金を引いた" ],
      # ---- 振込（Transfer$<振込ID>） ----
      [ B::TransferRequested, "振込の受付", :transfer, nil, "振込を受け付けた（このあと振込先へ入金する）" ],
      [ B::TransferCompleted, "振込の完了", :transfer, :check, "振込先への入金まで終わった" ],
      [ B::TransferFailed, "振込の失敗（組戻し）", :transfer, :alert, "振込先に入金できず、振込元へ戻した" ],
      [ B::TransferReversed, "振込の組戻し（取消）", :transfer, :undo, "完了した振込を、行員が取り消した（二人承認）" ],
      [ B::TransferScheduled, "予約振込の受付", :transfer, :calendar, "実行日に振り込む予約を受け付けた（まだ引き落とさない）" ],
      [ B::TransferStarted, "予約振込の実行", :transfer, :clock, "実行日になったので引き落とした" ],
      [ B::ScheduledTransferFailed, "予約振込の実行できず", :transfer, :alert, "実行日に引き落とせなかった（お金は動いていない）" ],
      [ B::TransferHeld, "振込の保留", :guard, nil, "高額なので、行員が確かめるまで入金を止めた" ],
      [ B::TransferReleased, "保留を通す", :guard, :check, "行員が確かめて、保留を外した" ],
      [ B::TransferCancelled, "振込の取消", :transfer, :close, "実行前の振込を、利用者が取り消した" ],
      [ B::TransferStopped, "振込の差し止め", :guard, :close, "実行前の振込を、行員が差し止めた" ],
      # ---- ちゅ〜るローン（Loan$<貸付ID>） ----
      [ B::LoanGranted, "ちゅ〜るローンの貸付", :loan, nil, "お金を貸した。返す額は借りた額に手数料（利息）を足した額" ],
      [ B::LoanRepaid, "ちゅ〜るローンの返済", :loan, :undo, "借りたお金の一部を返してもらった" ],
      [ B::LoanSettled, "ちゅ〜るローンの完済", :loan, :check, "借りたお金を全部返し終わった" ],
      # ---- 出金依頼（WithdrawalRequest$<依頼ID>） ----
      [ B::WithdrawalRequested, "出金の依頼", :request, nil, "利用者が窓口での出金を頼んだ（お金はまだ動かない）" ],
      [ B::WithdrawalRequestProcessed, "出金依頼の処理", :request, :check, "行員が依頼どおりに出金した" ],
      [ B::WithdrawalRequestRejected, "出金依頼のお断り", :request, :close, "行員が依頼を断った" ],
      [ B::WithdrawalRequestCancelled, "出金依頼の取消", :request, :undo, "利用者が依頼を取り消した" ],
      # ---- 二人承認（Approval$<申請ID>） ----
      [ A::ApprovalRequested, "承認の申請", :request, :key, "行員が、取消・組戻し・凍結の解除を申請した" ],
      [ A::ApprovalGranted, "承認", :request, :check, "申請した人とは別の行員が承認した" ],
      [ A::ApprovalExecuted, "承認した操作の実行", :request, :wrench, "承認した操作を銀行で実行した" ],
      [ A::ApprovalRejected, "申請の却下", :request, :close, "申請した人とは別の行員が却下した" ],
      [ A::ApprovalWithdrawn, "申請の取り下げ", :request, :undo, "申請した本人が取り下げた" ],
      # ---- 商店（Shop$main・Product$<商品>・Order$<注文ID>） ----
      [ S::ShopOpened, "商店の開店", :shop, nil, "ちゅ〜る商店が銀行に口座を開いた" ],
      [ S::ProductListed, "商品の登録", :shop, nil, "新しい商品を並べた" ],
      [ S::ProductPriceChanged, "値段の変更", :shop, nil, "商品の値段を変えた" ],
      [ S::StockAdded, "入荷", :shop, :arrow_in, "商品の在庫が増えた" ],
      [ S::StockAllocated, "在庫の引き当て", :shop, :arrow_out, "支払い済みの注文のために在庫を取り分けた（出荷）" ],
      [ S::OrderPlaced, "注文", :shop, :cart, "お買いものの注文を受けた" ],
      [ S::OrderPaymentRequested, "支払いの依頼", :shop, :send, "銀行に、購入者 → 商店 の振込を頼んだ" ],
      [ S::OrderPaid, "支払いの完了", :shop, :wallet, "支払いの振込が終わった" ],
      [ S::OrderPaymentFailed, "支払いの失敗", :shop, :alert, "残高不足などで支払えなかった" ],
      [ S::OrderFulfilled, "注文の完了", :shop, :check, "在庫を引き当てて、注文が終わった" ],
      [ S::OrderCancelled, "注文のキャンセル", :shop, :close, "支払いのあとで在庫が足りず、キャンセルした（このあと返金）" ],
      [ S::OrderRefundRequested, "返金の依頼", :shop, :undo, "銀行に、商店 → 購入者 の振込を頼んだ" ],
      [ S::OrderRefunded, "返金の完了", :shop, :check, "返金の振込が終わった" ],
      [ S::OrderRefundFailed, "返金の失敗", :shop, :alert, "返金できなかった（人の手で対応が必要）" ]
    ].freeze

    ENTRIES = ROWS.to_h do |klass, label, kind, icon, description|
      [ klass.name, Entry.new(type: klass.name, label:, kind:, icon: icon || KINDS.fetch(kind).icon, description:) ]
    end.freeze

    def self.entry(type)
      ENTRIES[type.to_s] || Entry.new(type: type.to_s, label: type.to_s.demodulize, kind: :other, icon: OTHER.icon,
                                      description: "まだ日本語の名前がない出来事")
    end

    def self.kind(key) = KINDS[key&.to_sym] || OTHER

    # 種類で絞り込むときの RES の of_type に渡すクラス
    def self.types_of(kind) = ROWS.select { |row| row[2] == kind.to_sym }.map(&:first)

    # ---- イベントがもともと書かれたストリーム（レーン図の「関係者」） ----
    # 口座側のイベントは Transfer$ などにもリンクされるが、もとは Account$。RES に聞かずに、イベントの種類と data から決める
    def self.home_stream(event)
      data = event.data
      case event
      when *B::ACCOUNT then "Account$#{data[:account_number]}"
      when *B::TRANSFER then "Transfer$#{data[:transfer_id]}"
      when *B::WITHDRAWAL_REQUEST then "WithdrawalRequest$#{data[:request_id]}"
      when *B::LOAN then "Loan$#{data[:loan_id]}"
      when *A::ALL then "Approval$#{data[:approval_id]}"
      when S::ShopOpened then "Shop$main"
      when *S::PRODUCT then "Product$#{data[:sku]}"
      when *S::ORDER then "Order$#{data[:order_id]}"
      end
    end

    # ---- 中身の項目 ----

    FIELD_LABELS = {
      account_number: "口座", holder_name: "名義", opened_on: "開設日", amount: "金額", memo: "メモ", reason: "理由",
      request_id: "出金依頼", transfer_id: "振込", counterparty: "相手の口座", from_account: "振込元", to_account: "振込先",
      reversed_event_id: "取り消した出来事", interest_date: "利息の対象日", base_balance: "もとになった残高",
      annual_rate: "年利", carry: "繰り越す端数", execute_on: "実行日", threshold: "保留のしきい値", refunded: "払い戻した",
      withdrawal_event_id: "出金の出来事", approval_id: "承認の申請", kind: "申請の種類", ledger_event_id: "取り消す通帳の行",
      summary: "説明", requested_by: "申請した人", approved_by: "承認した人", rejected_by: "却下した人",
      event_ids: "実行した出来事", sku: "商品", name: "商品名", emoji: "絵文字", price: "値段", quantity: "数",
      order_id: "注文", buyer_account: "買った人の口座", lines: "品物", total: "合計",
      loan_id: "ちゅ〜るローン", principal: "借りた額", fee: "手数料（利息）", outstanding: "返す額の残り"
    }.freeze
    # metadata（RES と各パックが付ける付帯情報）。request_id は data の「出金依頼」とは別物（Rails のリクエスト）
    METADATA_LABELS = {
      actor: "だれが", timestamp: "記帳した時刻", valid_at: "起算日時（本当はいつのことか）",
      correlation_id: "ひとつながりの番号", causation_id: "きっかけの出来事", request_id: "画面のリクエスト",
      remote_ip: "接続元", approval_id: "承認の申請", requested_by: "申請した人", approved_by: "承認した人",
      resident: "住民（ねこ町の暮らし。packs/simulation の窓口役が付ける印）"
    }.freeze

    MONEY_FIELDS = %i[amount base_balance threshold price total principal fee outstanding].freeze
    ACCOUNT_FIELDS = %i[account_number counterparty from_account to_account buyer_account].freeze
    ACTOR_FIELDS = %i[actor requested_by approved_by rejected_by].freeze
    EVENT_FIELDS = %i[reversed_event_id withdrawal_event_id ledger_event_id causation_id event_ids].freeze
    # 値がほかのストリームの ID になっている項目（つながりの図で、そのストリームもたどる）
    STREAM_FIELDS = {
      transfer_id: "Transfer$", order_id: "Order$", request_id: "WithdrawalRequest$", approval_id: "Approval$", sku: "Product$",
      loan_id: "Loan$"
    }.freeze
    APPROVAL_KINDS = { "reversal" => "入出金の取消", "transfer_reversal" => "振込の組戻し", "unfreeze" => "凍結の解除" }.freeze

    def self.field_label(key, metadata: false)
      (metadata ? METADATA_LABELS : FIELD_LABELS)[key.to_sym] || key.to_s
    end
  end
end
