# ねこの実況（TODO の X）: 出来事1件を、ねこのちゅーるのひとこと（文とねこの表情）にする。
#   例: TransferRequested → 「いまオルカさんからミケさんへ 300 ちゅ〜る！」（うれしい）
# 文は出来事の種類ごとに LINES で決める。LINES にない出来事は Catalog の日本語の名前で「〜があったにゃ」。
#
# だれが見るかで、出す名前を変える（このパックはログインのパックに依存しないので、見る人の口座番号を受け取る）。
#   - own_accounts: nil … 行員の画面。口座は名義で「オルカさん」、行員は names の名前で出す
#   - own_accounts: 口座番号の配列 … 利用者の画面。自分の口座は「あなた」、ほかの口座は「ほかのお客さま」（商店の口座だけは商店の名前）。
#     行員の名前は出さない。見てよい出来事かどうかは呼ぶ側（MyEvents::EventScope）が先に確かめる
# 読むだけ（公開の読み取りモデルで、振込の相手や商品の名前を引く）
module EventLens
  class Commentary
    include Ui::FormatHelper
    include ActionView::Helpers::NumberHelper

    # face は Ui::ThemeHelper::CAT_FACES のどれか。bounce: うれしいときは弾む
    Line = Data.define(:text, :face) do
      def bounce = face == :happy
    end

    B = Banking::Events
    S = Shop::Events
    A = Approvals::Events

    # 出来事の種類 → [表情, 文を作る手続き]。手続きの中の who / churu / product などは、このクラスのメソッド
    LINES = {
      # ---- 口座 ----
      B::AccountOpened => [ :happy, ->(d) { "#{who(d[:account_number])}の口座ができたにゃ！ ようこそにゃ〜" } ],
      B::AccountClosed => [ :sad, ->(d) { "#{who(d[:account_number])}の口座がとじられたにゃ… またいつでも来てにゃ" } ],
      B::MoneyDeposited => [ :happy, ->(d) { "#{who(d[:account_number])}の口座に #{churu(d[:amount])} 入金にゃ！" } ],
      B::MoneyWithdrawn => [ :normal, ->(d) { "#{who(d[:account_number])}に、窓口で #{churu(d[:amount])} お渡ししたにゃ" } ],
      B::AccountFrozen => [ :surprised, ->(d) { "#{who(d[:account_number])}の口座が凍結されたにゃ！ しばらくお金を動かせないにゃ" } ],
      B::AccountUnfrozen => [ :happy, ->(d) { "#{who(d[:account_number])}の口座の凍結がとけたにゃ。よかったにゃ〜" } ],
      B::TransferDebited => [ :normal, ->(d) { "#{who(d[:account_number])}の口座から、振込の #{churu(d[:amount])} を引き落としたにゃ" } ],
      B::TransferCredited => [ :happy, lambda { |d|
        "#{who(d[:counterparty])}から#{who(d[:account_number])}へ、#{churu(d[:amount])} とどいたにゃ！"
      } ],
      B::TransferRefunded => [ :sad, ->(d) { "振り込めなかった #{churu(d[:amount])} が、#{who(d[:account_number])}へ戻ったにゃ" } ],
      B::TransferCreditReversed => [ :sad, lambda { |d|
        "組戻しで、#{who(d[:account_number])}の口座から #{churu(d[:amount])} 引き戻したにゃ"
      } ],
      B::DepositReversed => [ :surprised, ->(d) { "まちがえた入金 #{churu(d[:amount])} を取り消したにゃ" } ],
      B::WithdrawalReversed => [ :surprised, ->(d) { "まちがえた出金 #{churu(d[:amount])} を取り消して、口座に戻したにゃ" } ],
      B::InterestPaid => [ :happy, ->(d) { "#{who(d[:account_number])}の口座に、利息が #{churu(d[:amount])} ついたにゃ。ちりつもにゃ〜" } ],
      B::LoanDisbursed => [ :surprised, ->(d) { "#{who(d[:account_number])}が、ちゅ〜るローンで #{churu(d[:amount])} 借りたにゃ！ 返すのを忘れないでにゃ" } ],
      B::LoanRepaymentDebited => [ :normal, ->(d) { "#{who(d[:account_number])}が、ちゅ〜るローンを #{churu(d[:amount])} 返したにゃ" } ],
      # ---- 振込 ----
      B::TransferRequested => [ :happy, ->(d) { "いま#{who(d[:from_account])}から#{who(d[:to_account])}へ #{churu(d[:amount])}！" } ],
      B::TransferCompleted => [ :happy, ->(d) { "#{transfer_route(d[:transfer_id])}振込、ぶじに終わったにゃ！" } ],
      B::TransferFailed => [ :sad, ->(d) { "#{transfer_route(d[:transfer_id])}振込がうまくいかなかったにゃ… お金は振込元へ戻すにゃ" } ],
      B::TransferReversed => [ :surprised, ->(d) { "#{transfer_route(d[:transfer_id])}振込を、組戻しで取り消したにゃ" } ],
      B::TransferScheduled => [ :normal, lambda { |d|
        "#{who(d[:from_account])}から#{who(d[:to_account])}へ、#{jp_date(d[:execute_on].to_date)}に #{churu(d[:amount])} の予約振込にゃ"
      } ],
      B::TransferStarted => [ :normal, ->(d) { "予約していた#{transfer_route(d[:transfer_id])}振込、きょう実行するにゃ！" } ],
      B::ScheduledTransferFailed => [ :sad, ->(d) { "予約の#{transfer_route(d[:transfer_id])}振込を実行できなかったにゃ… お金は動いてないにゃ" } ],
      B::TransferHeld => [ :surprised, ->(_d) { "大きな振込だにゃ！ 行員さんが確かめるまで、ちょっと待ってもらうにゃ" } ],
      B::TransferReleased => [ :happy, ->(_d) { "確かめ終わったにゃ。保留していた振込を進めるにゃ！" } ],
      B::TransferCancelled => [ :normal, ->(d) { "#{transfer_route(d[:transfer_id])}振込を取り消したにゃ" } ],
      B::TransferStopped => [ :surprised, ->(d) { "#{transfer_route(d[:transfer_id])}振込が、差し止められたにゃ！" } ],
      # ---- ちゅ〜るローン ----
      B::LoanGranted => [ :normal, lambda { |d|
        "#{who(d[:account_number])}に #{churu(d[:principal])} 貸したにゃ。返すのは手数料こみで #{churu(d[:total])} にゃ"
      } ],
      B::LoanRepaid => [ :happy, ->(d) { "ちゅ〜るローン、のこりは #{churu(d[:outstanding])} にゃ。がんばれにゃ〜" } ],
      B::LoanSettled => [ :happy, ->(d) { "#{who(d[:account_number])}が、ちゅ〜るローンを全部返し終わったにゃ！ えらいにゃ〜" } ],
      # ---- 出金依頼 ----
      B::WithdrawalRequested => [ :normal, lambda { |d|
        "#{who(d[:account_number])}から、#{churu(d[:amount])} の出金の依頼が来たにゃ。窓口で待っててにゃ"
      } ],
      B::WithdrawalRequestProcessed => [ :happy, ->(d) { "#{who(d[:account_number])}の出金の依頼、#{churu(d[:amount])} お渡ししたにゃ！" } ],
      B::WithdrawalRequestRejected => [ :sad, ->(d) { "#{who(d[:account_number])}の出金の依頼は、お断りになったにゃ…" } ],
      B::WithdrawalRequestCancelled => [ :normal, ->(d) { "#{who(d[:account_number])}の出金の依頼が取り消されたにゃ" } ],
      # ---- 二人承認（行員の画面だけに出る） ----
      A::ApprovalRequested => [ :surprised, ->(d) { "#{staff(d[:requested_by])}が「#{d[:summary]}」を申請したにゃ。だれか見てあげてにゃ" } ],
      A::ApprovalGranted => [ :happy, ->(d) { "#{staff(d[:approved_by])}が承認したにゃ！ 二人そろったにゃ" } ],
      A::ApprovalExecuted => [ :normal, ->(_d) { "承認した操作を、銀行で実行したにゃ" } ],
      A::ApprovalRejected => [ :sad, ->(d) { "#{staff(d[:rejected_by])}が申請を却下したにゃ" } ],
      A::ApprovalWithdrawn => [ :normal, ->(_d) { "申請が取り下げられたにゃ" } ],
      # ---- 商店 ----
      S::ShopOpened => [ :happy, ->(_d) { "ちゅ〜る商店が開店したにゃ！ いらっしゃいませにゃ〜" } ],
      S::ProductListed => [ :happy, ->(d) { "新しい商品「#{d[:emoji]}#{d[:name]}」（#{churu(d[:price])}）が並んだにゃ！" } ],
      S::ProductPriceChanged => [ :surprised, ->(d) { "「#{product(d[:sku])}」の値段が #{churu(d[:price])} になったにゃ" } ],
      S::StockAdded => [ :happy, ->(d) { "「#{product(d[:sku])}」が #{d[:quantity]} こ入荷したにゃ！" } ],
      S::StockAllocated => [ :normal, ->(d) { "「#{product(d[:sku])}」を #{d[:quantity]} こ、注文のために取り分けたにゃ" } ],
      S::OrderPlaced => [ :happy, lambda { |d|
        "#{who(d[:buyer_account])}が #{items(d[:lines])} を注文したにゃ！（合計 #{churu(d[:total])}）"
      } ],
      S::OrderPaymentRequested => [ :normal, ->(_d) { "お買いものの代金を、銀行に振り込んでもらうにゃ" } ],
      S::OrderPaid => [ :happy, ->(_d) { "お買いものの支払いが終わったにゃ！" } ],
      S::OrderPaymentFailed => [ :sad, ->(_d) { "お買いものの支払いができなかったにゃ… 残高を見てみてにゃ" } ],
      S::OrderFulfilled => [ :happy, ->(_d) { "ご注文の品、ぜんぶそろったにゃ！ まいどありにゃ〜" } ],
      S::OrderCancelled => [ :sad, ->(_d) { "在庫が足りなくて、注文をキャンセルしたにゃ… お金は返すにゃ" } ],
      S::OrderRefundRequested => [ :normal, ->(_d) { "お買いものの返金を、銀行に頼んだにゃ" } ],
      S::OrderRefunded => [ :normal, ->(_d) { "返金が終わったにゃ。またのお越しをにゃ" } ],
      S::OrderRefundFailed => [ :sad, ->(_d) { "返金できなかったにゃ！ 行員さんに見てもらうにゃ" } ]
    }.transform_keys(&:name).freeze

    def initialize(names:, own_accounts: nil)
      @names = names
      @own = own_accounts&.map(&:to_s)
    end

    def line(event)
      face, text = LINES[event.event_type]
      text = face ? instance_exec(event.data, &text) : "#{Catalog.entry(event.event_type).label}があったにゃ"
      Line.new(text: "#{resident_mark(event)}#{text}", face: face || :normal)
    end

    private

    def customer_view? = !@own.nil?

    # ねこ町の住民（packs/simulation）がした出来事には、metadata に住民の名前の印がある
    def resident_mark(event)
      resident = event.metadata[:resident]
      resident ? "［住民の#{resident}］" : ""
    end

    # 口座の持ち主の呼び名
    def who(number)
      number = number.to_s
      return staff_who(number) unless customer_view?
      return (@own.one? ? "あなた" : "あなた（口座 #{number}）") if @own.include?(number)

      shop_account?(number) ? Shop::Store::SHOP_NAME : "ほかのお客さま"
    end

    def staff_who(number)
      holder = @names.holder(number)
      return "口座 #{number}" if holder.blank?

      shop_account?(number) ? holder : "#{holder}さん"
    end

    def shop_account?(number) = @names.holder(number) == Shop::Store::SHOP_NAME

    # 行員（actor の staff:<id>）。利用者の画面には出さない
    def staff(actor) = customer_view? ? "行員さん" : @names.actor(actor)

    # 「オルカさんからミケさんへの」。振込の読み取りモデルがまだなければ空（「振込…」だけにする）
    def transfer_route(transfer_id)
      transfer = ::Transfer.find_by(transfer_id:)
      transfer ? "#{who(transfer.from_account)}から#{who(transfer.to_account)}への" : ""
    end

    def product(sku) = @names.product(sku) || sku

    def items(lines)
      lines = Array(lines).map { it.to_h.symbolize_keys }
      first = "「#{lines.first&.dig(:name)}」"
      lines.size > 1 ? "#{first}など #{lines.size} 品" : first
    end
  end
end
