# ふせんの壁（イベントストーミング）に貼る、青（命令）と紫（方針・係）のふせんのことば。
# イベントストアには「命令」も「係」も残らないので、出来事の種類と actor から「たぶんこう頼まれた」を言葉にする
module EventViewer
  module WallWords
    B = Banking::Events
    S = Shop::Events
    A = Approvals::Events

    # [出来事, 命令]。1回の処理（ふせんのまとまり）に出来事がいくつかあるときは、この表で上にあるものの命令にする
    # （注文の処理には振込の引き落としも入るが、命令は「注文する」）
    COMMANDS = [
      [ S::OrderPlaced, "注文する" ],
      [ S::OrderCancelled, "注文をキャンセルして返金を頼む" ],
      [ S::OrderPaid, "支払いを確かめて品物を引き当てる" ],
      [ S::OrderPaymentFailed, "支払えなかった注文を止める" ],
      [ S::OrderRefunded, "返金を確かめる" ],
      [ S::OrderRefundFailed, "返金できなかったと記す" ],
      [ A::ApprovalRequested, "承認を申請する" ],
      [ A::ApprovalGranted, "承認する" ],
      [ A::ApprovalRejected, "却下する" ],
      [ A::ApprovalWithdrawn, "申請を取り下げる" ],
      [ B::TransferReleased, "保留を通す" ],
      [ B::TransferStopped, "振込を差し止める" ],
      [ B::TransferCancelled, "振込を取り消す" ],
      [ B::TransferStarted, "予約の振込を引き落とす" ],
      [ B::ScheduledTransferFailed, "予約の振込を引き落とす" ],
      [ B::TransferScheduled, "振込を予約する" ],
      [ B::TransferCredited, "振込先へ入金する" ],
      [ B::TransferRefunded, "振込元へ戻す" ],
      [ B::TransferRequested, "振り込む" ],
      [ B::WithdrawalRequested, "出金を頼む" ],
      [ B::WithdrawalRequestProcessed, "依頼どおりに出金する" ],
      [ B::WithdrawalRequestRejected, "出金の依頼を断る" ],
      [ B::WithdrawalRequestCancelled, "出金の依頼を取り消す" ],
      [ B::AccountOpened, "口座を開く" ],
      [ B::AccountClosed, "口座をとじる" ],
      [ B::MoneyDeposited, "入金する" ],
      [ B::AccountFrozen, "口座を凍結する" ],
      [ B::AccountUnfrozen, "凍結を解く" ],
      [ B::DepositReversed, "入金を取り消す" ],
      [ B::WithdrawalReversed, "出金を取り消す" ],
      [ B::TransferReversed, "振込を組戻しする" ],
      [ B::InterestPaid, "利息をつける" ],
      [ S::ShopOpened, "商店を開く" ],
      [ S::ProductListed, "商品を並べる" ],
      [ S::ProductPriceChanged, "値段を変える" ],
      [ S::StockAdded, "入荷する" ]
    ].map { |klass, label| [ klass.name, label ] }.freeze

    # 紫のふせん: 人ではなく、出来事を購読して次の処理をする係（ジョブ）。actor で見分ける
    Policy = Data.define(:label, :rule)
    POLICIES = {
      "transfer-settlement" => Policy.new("振込の確定の係", "引き落としや「保留を通す」があったら、振込先へ入金する（入れなければ振込元へ戻す）"),
      "shop-payment" => Policy.new("商店の支払いの係", "商店の振込が終わったら、在庫を引き当てる（足りなければ返金を頼む）"),
      "transfer-scheduler" => Policy.new("予約振込の係", "実行日になったら、予約の振込を引き落とす"),
      "interest" => Policy.new("利息の係", "毎日、前の日の残高に利息をつける")
    }.freeze

    def self.command(events)
      types = events.map(&:event_type)
      COMMANDS.find { |type, _| types.include?(type) }&.last || "「#{EventLens::Catalog.entry(types.first).label}」を起こす"
    end

    def self.policy(actor) = POLICIES[actor.to_s]
  end
end
