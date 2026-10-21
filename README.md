# ちゅーる銀行 🐟

通貨「ちゅ〜る」の銀行ごっこ。Rails 8 + Rails Event Store（RES）で、イベントソーシングと
Hotwire・Solid Queue・Solid Cable など Rails 標準の機能を一通り使ってみるためのアプリ。

## 起動

```bash
bin/rails db:prepare   # 開発用の管理者・利用者・口座も入る（db/seeds.rb）
bin/dev            # http://localhost:3000 （Solid Queue のワーカーも Puma の中で動く）
bin/test           # ルートとすべてのパックのテスト
bin/ci             # rubocop / packwerk / brakeman / テスト を全部
```

- 環境: WSL の Ubuntu 24.04、Ruby は mise（`mise.toml`）、バージョン管理は jj
- ログイン: 開発用のアカウントとパスワードは `db/seeds.rb`（管理者 1 人と、オルカ・ジンジベル・ミケ）
- `/` … 利用者画面（自分の口座だけ）、`/admin` … 管理画面（行員。管理者だけ）
- `/res` … RES Browser（イベントストアの中身を見る。管理者だけ）
- `/notices` … 銀行からのお知らせ（利用者）、`/admin/notices` … お知らせを出す・直す・掲載終了（行員）

## パッケージ（packwerk）

| パッケージ | 中身 | 依存してよい先 |
|---|---|---|
| `.`（ルート） | JS（Stimulus）・CSS、画面へのライブ更新（`BroadcastRefreshJob`）、イベントストア本体 | platform, banking, identity |
| `packs/admin` | 管理画面 `/admin`（`Admin::`）。全口座の開設・入出金・振込・凍結、振込一覧。管理者だけ | platform, banking, identity, ui |
| `packs/customer` | 利用者画面 `/`（`Customer::`）。自分の口座の一覧・通帳・時点残高、自分の口座からの振込。お知らせはレイアウトで `notices_inbox` を1回呼ぶだけ | platform, banking, identity, ui, notices |
| `packs/identity` | ログイン（Rails 8 の `generate authentication`）、`User#admin`、利用者と口座のひも付け（`account_ownerships`）。外から使えるのは `app/public`（`User` / `Current` / `Authentication`） | platform |
| `packs/banking` | 銀行ドメイン。外から使えるのは `app/public` だけ（`Banking::Bank` ほか） | platform |
| `packs/shop` | ちゅ〜る商店（商品・在庫・注文）と `/shop` の画面（商品と在庫の管理 `/shop/admin` も）。外から使えるのは `app/public` だけ（`Shop::Store` ほか） | platform, banking, identity, ui |
| `packs/ui` | 画面の共通部品: 外枠のレイアウト（`layouts/application`。`content_for :nav` と `:page_top` で差し込む）、ねこテーマ（`layouts/cat` と `ui/cat.css`）、`Ui::FormatHelper`（`churu` / `jp_date` / `jp_time`） | platform, identity |
| `packs/notices` | 銀行からのお知らせ・お願い・メンテナンス（ふつうの ActiveRecord）。行員の画面 `/admin/notices`、利用者の `/notices`。外から使えるのは `app/public`（`Notices::InboxHelper` / `Notices::Board`） | platform, identity, ui |
| `packs/mcp` | MCP サーバー（`/mcp`）。ツールは `app/mcp/churu_mcp/tools` | platform, banking |
| `packs/platform` | `ApplicationRecord` / `ApplicationJob` / `ApplicationController` などの土台 | なし |

- `bin/packwerk check` で、依存（`enforce_dependencies`）と非公開の参照（`enforce_privacy`、packwerk-extensions）を検査する
- 各パックは自分の `config/initializers` で自分のイベント購読だけを書く。イベントストア本体はルート
- パックのテストは `packs/<名前>/test`。`bin/test` でまとめて流れる
- ルーティングも各パックの `config/routes/<名前>.rb` に書き、`config/routes.rb` から `draw :<名前>` で読む
- admin と customer は互いに依存しない。銀行は `User` を知らない（口座番号だけでつながる）
- 画面のパック（admin / customer / shop）は、ベースコントローラで `helper Ui::FormatHelper` して packs/ui に依存する。
  レイアウトはテンプレート名（`render template: "layouts/application"` / `"layouts/cat"`）で使うので packwerk には見えないが、
  `Ui::FormatHelper` の参照が「ui を使っている」しるしになり、`bin/packwerk check` で依存の宣言漏れが見つかる

## 認証と権限

- ログインは `packs/identity`（Rails 8 の `generate authentication` がもと。パスワード再設定は入れていない）。
  画面のパックのベースコントローラ（`Admin::ApplicationController` / `Customer::ApplicationController` /
  `Shop::ApplicationController`）で `Authentication` を include する
- 管理画面は `User#admin` だけ。そうでなければ 404（管理画面があることも見せない）。`/res` もルーティングの制約で管理者だけ
- 利用者画面は `account_ownerships` でひも付いた口座だけ。他人の口座は口座ページ・時点残高・振込とも 404。
  入出金と凍結は行員だけ。振込先には全口座（解約済みを除く）を選べる
- 利用者画面は見た目も別（ねこ・ちゅ〜るのテーマ、`packs/ui/app/assets/stylesheets/ui/cat.css`。`layouts/cat` が読み込む）。`body.cat-theme` の下だけに効き、管理画面は今の見た目のまま
- 商店（`/shop`）もログイン必須。権限は「ちゅ〜る商店」の節を参照
- だれの操作かは、イベントの metadata の actor に `admin:<メール>` / `customer:<メール>` で残る
- Action Cable もログインが必要（`ApplicationCable::Connection`）。購読できるのは画面に埋め込まれた署名つきのストリームだけ

### packwerk の気づき（商店を作って）

- 商店は銀行の公開 API（`Bank` / `Events` / 例外 / 読み取りモデル）だけで作れた。プロセスマネージャは
  銀行のイベント（`TransferCompleted` / `TransferFailed`）を購読するので、銀行側の変更はいらない
- 商店のテストで銀行の非公開ジョブ（`Transfers::SettleJob`）だけを流そうとして privacy 違反になった。
  `perform_enqueued_jobs(except: Shop::PaymentJob)` のように「自分のジョブ以外」と書けば済む
- 画面の土台（`ApplicationController`・レイアウト・`churu` などのヘルパー・`account_path`）はルートにあり、
  パックからは依存できない。商店は `ActionController::Base` から直接作り、レイアウトとヘルパーは名前で借りていた。
  定数ではないので packwerk には見えない依存
  → TODO の N で、レイアウトとヘルパーを UI 用の土台パック `packs/ui` に移した。packs/platform に置かなかったのは、
  レイアウトがログイン中の利用者（identity の `Current`）を使うから（platform は「どこにも依存しない」）。
  ヘルパーは `Ui::FormatHelper` と名前空間つきの定数にして、各ベースコントローラで `helper Ui::FormatHelper` と書く。
  Rails は既定で全ヘルパーをどの画面にも入れる（`include_all_helpers`）ので書かなくても動くが、書くことで依存が packwerk に見える

## しくみ

```
Web / MCP / コンソール
   │  Banking::Bank（唯一の入口。actor を metadata に残す。dry_run あり）
   ▼
Banking::Account（集約: 業務ルール。残高はイベントから計算）
   │  publish（ストリーム Account$<口座番号>、expected_version で同時更新を防ぐ）
   ▼
イベントストア（event_store_events）──同期──▶ Projections::AccountProjection
   │                                           → accounts / ledger_entries（画面用の読み取りモデル）
   └─コミット後に非同期（Active Job / Solid Queue）─▶ BroadcastRefreshJob
                                                     → Turbo の refresh を Solid Cable で配信（morph）
```

- **正はイベントストア**。`accounts` / `ledger_entries` は画面用のキャッシュで、作り直せる
- **起算日と記帳日**: 入出金の起算日は RES の `valid_at`、記帳日は `timestamp`。
  `Banking::Statement` で「起算日基準（as_of）」と「記帳日基準（as_at）」の時点残高を出せる
- **ドライラン**: `Banking::Bank` の各操作は `dry_run: true` で、書き込まずに結果だけ返す。
  Web の入出金・振込は「確認（ドライラン）→ 確定」の2段階

## 振込（プロセスマネージャ）

```
Bank#transfer（同期・1トランザクション）
  Account$<振込元>  … TransferDebited（残高不足ならここで失敗）
  Transfer$<id>     … TransferRequested            ※口座側のイベントも Transfer$<id> にリンク
        │ コミット後に Solid Queue へ
        ▼
Transfers::SettleJob → Bank#settle_transfer（何度動いても1回分だけ）
  ├ 入金できた   … Account$<振込先> TransferCredited → Transfer$<id> TransferCompleted
  └ できなかった … Account$<振込元> TransferRefunded（組戻し）→ Transfer$<id> TransferFailed
```

- ジョブは `CorrelatedHandler` で correlation_id / causation_id を引き継ぐ。RES Browser の
  `Transfer$<id>` ストリームで、引き落とし → 入金（または組戻し）までを1か所で辿れる
- 振込先が凍結中だと、確認画面で「組戻しになります」と警告したうえで受け付ける（補償の動きを見るため）

## 利息（日次）

`Interest::PayJob` が `config/recurring.yml` で毎日 0:05（東京）に動き、`Bank#pay_interest` で前日分を払う。

- **元になる残高**: 前日の終わりの残高（起算日基準 = `Banking::Statement` の `as_of`）。あとから過去日付で
  入金しても、すでに払った利息は計算し直さない
- **利率**: 年利。日割りは年利 ÷ 365（うるう年も 365）。既定は 36.5%（= 1日 0.1%）で、
  環境変数 `CHURU_ANNUAL_INTEREST_RATE`（`packs/banking/config/initializers/banking_interest.rb`）で変える
- **端数**: 整数部分だけ払い、1 未満は口座ごとに分数のまま翌日へ繰り越す（切り捨てて消えない）。
  払う額が 0 の日も `InterestPaid`（amount: 0, carry: 端数）を書くが、通帳と時点残高には載せない
- **1日1回**: 口座の集約が「どの日の利息を払ったか」を覚えているので、ジョブが二重に動いても・リトライしても1回だけ
- **凍結中**は付ける（お金は口座にある）。**残高 0・解約済み**には付けない
- 利息の起算日（valid_at）は対象日の翌日 0:00。止まっていて動かなかった日は自動では払わない
  （`Bank#pay_interest(date: …)` で手で流せる）

## 取消（逆仕訳）と組戻し

元のイベントは消さず、逆向きのイベントで相殺する。残高は `Banking::Events.balance_delta` を通るので、
集約・読み取りモデル・`Banking::Statement` のどれから見てもずれない。

| 対象 | API | イベント | 条件 |
|---|---|---|---|
| 入金 | `Bank#reverse(number, event_id, reason:)` | `DepositReversed` | 残高が足りること（使ってしまった入金は取り消せない） |
| 出金 | 同上 | `WithdrawalReversed` | |
| 完了した振込 | `Bank#reverse_transfer(transfer_id, reason:)` | 振込先 `TransferCreditReversed` → 振込元 `TransferRefunded` → `Transfer$` `TransferReversed` | 振込先の残高が足りること。処理中・失敗（組戻し済み）は不可 |

- 二重取消・取消の取消はできない（`InvalidState`）。振込のイベントは `reverse` では取り消せない（`NotFound`）
- 銀行側の訂正なので凍結中の口座でもできる。解約済みは不可。理由（`reason`）は必須
- 起算日は取消した時点（過去の時点残高は書き換えない）
- 通帳: 取消の行は `reversal_of`、元の行は `reversed_by` に相手のイベント ID が入る
  （`LedgerEntry#original_entry` / `#reversal_entry`）。振込は `transfers.status = "reversed"`

## 読み取りモデルの作り直し

```bash
bin/rails churu:rebuild_projections
```

`accounts` / `ledger_entries` / `transfers` を空にして、イベントストアの全イベントを書かれた順に
同期プロジェクション（`Projections.all`）へ流し直す。1トランザクションで行い、非同期ハンドラ
（振込の `SettleJob`、画面の `BroadcastRefreshJob`）は動かさない。

## 画面から使う Banking::Bank の API

すべて `dry_run: true` で「確認 → 確定」の2段階にでき、`Outcome`（`balance_before` / `balance_after` / `events` /
`warnings`）を返す。失敗は `Banking::Error` の子クラス（`NotFound` / `InvalidState` / `InsufficientFunds` /
`ConcurrentModification`）か、入力まちがいの `ArgumentError`。

| やりたいこと | 呼び方 | 画面での目安 |
|---|---|---|
| 入出金の取消 | `bank.reverse(number, entry.event_id, reason:, dry_run:)` | `LedgerEntry#reversible?` の行に「取消」。取消済みは `reversed?`、取消の行は `reversal?` |
| 振込の組戻し | `bank.reverse_transfer(transfer.transfer_id, reason:, dry_run:)` | `Transfer#reversible?`（完了）の振込に「組戻し」。Outcome は振込元の口座 |
| 利息を手で払う | `bank.pay_interest(date:, dry_run:)` → `[Outcome]` / 1口座なら `bank.pay_interest_to(number, date:, dry_run:)` → `Outcome` か `nil` | 行員の画面向け。ふだんはジョブに任せる |
| 利率の表示 | `Banking::Bank.annual_interest_rate`（文字列。例 `"0.365"`） | |

通帳の種類（`LedgerEntry::KIND_LABELS`）に `interest`（利息）・`deposit_reversal` / `withdrawal_reversal`（取消）・
`transfer_reversal`（組戻しの引き戻し）が増えた。振込の状態（`Transfer::STATUS_LABELS`）に `reversed` が増えた。

### 管理画面での取消・組戻し・利息（packs/admin）

どれも入出金・振込と同じく Turbo Frame の中で「入力 → 確認（ドライラン）→ 確定（`_top` へ）」。

| 画面 | 場所 | 確認画面で見せるもの |
|---|---|---|
| 入出金の取消 | 口座ページの通帳の「取消」→ Frame `reversal`（`/admin/accounts/:number/reversals/new?event_id=`） | 理由・残高の変化・発生するイベント |
| 振込の組戻し | 振込一覧と口座ページの通帳の「組戻し」→ Frame `reversal`（`/admin/transfers/:id/reversals/new`） | 振込元・振込先それぞれの残高の変化・イベント。口座ページから来たら確定後はその口座へ戻る（`back_to`） |
| 利息（全口座） | メニューの「利息」（`/admin/interest`）。利率の表示と日付 → Frame `interest` | 口座ごとの元の残高・支払額・繰り越す端数。支払い済み・残高 0・解約済みの口座はその旨 |
| 利息（1口座） | 口座ページの「利息」カード → Frame `interest` | 同上（1行） |

- 利息の日付は昨日まで（その日の終わりの残高にかかるので）。払う口座が無ければ確定ボタンを出さず、
  それでも確定が来たら「何もしませんでした」と出す（2回目は払われない）。確定後は `/admin/interest?date=` に戻り、
  その日の「支払い済み n 口座・まだ払っていない m 口座」を出す（flash は直後のライブ更新の morph で消えることがあるため）
- 通帳: 取り消された行は金額に取り消し線と「取消済み → 取消の行」、取消の行は「← 元の行」へのリンク（`#dom_id`）。
  組戻しした振込は「組戻し済み」と理由。利用者画面は「取消済み」のバッジだけ（ボタンは出さない）
- 管理画面だけの CSS は `packs/admin/app/assets/stylesheets/admin/admin.css`（`layouts/admin` が `data-turbo-track="dynamic"` で読む）

## ちゅ〜る商店（packs/shop）

`/shop`。銀行とは別のドメインで、集約とイベントを自前で持つ。支払いと返金は `Banking::Bank#transfer`
（購入者 ⇄ 商店の口座「ちゅ〜る商店」）だけを使い、銀行は商店を知らない。

```
Shop::Store#place_order（同期・1トランザクション。銀行の引き落としも同じトランザクション）
  Order$<id> … OrderPlaced → OrderPaymentRequested（振込IDは ShopTransfer$<振込ID> にリンク）
        │ 銀行の SettleJob → TransferCompleted / TransferFailed
        ▼
Shop::PaymentJob（銀行のイベントを購読）→ Store#settle_transfer（何度動いても1回分だけ）
  ├ 支払い完了 → Product$<sku> StockAllocated → OrderPaid → OrderFulfilled
  │   在庫不足 → OrderPaid → OrderCancelled → OrderRefundRequested（商店 → 購入者 の振込）→ OrderRefunded
  └ 支払い失敗（残高不足・組戻し）→ OrderPaymentFailed
```

- **在庫は支払い前に引き当てない**。注文の確認で「在庫が足りないので返金になります」と警告するだけで、
  引き当ては支払いが終わってから。支払い待ちの注文が在庫を抱え込む（期限切れの解放が要る）のを避け、
  そのかわり支払い後に足りなければ返金する（補償）。銀行の「凍結中の口座への振込 → 組戻し」と同じ考え方
- **二重実行**: 注文IDは確認画面で決めるので、「注文する」が2回送られても2回目は `AlreadyPlaced`。
  ジョブが2回動いても、注文の状態と集約の `expected_version` で1回分しか引き当て・返金しない
- 注文 → 振込 → 引き当て（返金）は同じ correlation_id を持つ（RES Browser で辿れる）
- 開発用の商品は `bin/rails db:seed`（商店の口座も開く）

### 認証と権限（TODO の N）

- `/shop` はログイン必須（`Shop::ApplicationController` で `Authentication` を include）
- **購入者はログイン中の利用者にひも付いた口座（`account_ownerships`）だけ**。口座が複数あれば「支払う口座」で選べる
  （選んだ口座はセッションに持つが、使うたびに自分の口座の中から探し直す。他人の口座番号を送っても無視）。
  ひも付いた口座がなければ注文できない
- 注文履歴は自分の口座の分だけ。他人の注文ページは 404（あるかどうかも見せない）
- **行員が商店で買う場合**: 行員も「自分にひも付いた口座」でだけ買える。行員だからといって利用者の口座で
  代わりに買うことはできない（代理購入は銀行の業務ではないし、他人の口座から引き落とす入口を増やさない）。
  シードの行員には口座がないので、買うには口座を開いてひも付ける。行員は注文ページを全員分見られる（商品と在庫の管理の「最近の注文」から辿るため）
- **商品の登録・値段・入荷・商店の口座を開く**のは行員（`User#admin`）だけ。`Shop::Admin::ApplicationController` で、行員でなければ 404
- だれの操作かは、商店のイベントの metadata の actor に `shop:<メール>` で残る
- 見た目: 利用者にはねこテーマ（`layouts/shop/customer` → `layouts/cat`）、行員には管理画面と同じ見た目
  （`layouts/shop/staff` → `layouts/application`）。どちらも packs/ui のレイアウト

**商品の管理を `/admin`（packs/admin）に寄せず、`/shop/admin`（packs/shop）に残した理由**:
管理画面に寄せると admin → shop の依存ができ、admin はドメインが増えるたびに全部に依存する「何でも屋」になる。
商店の画面はもともと全部 shop の中（非公開）にあり、管理の画面だけ外に出すと `Shop::Store` の使い方が2か所に割れる。
shop に残せば、shop が増やす依存は identity（ログインと `User#admin`）と ui（見た目）だけで、admin は shop を知らないまま。
管理画面のメニューの「商店の管理」はリンク（ルート名）だけで、定数の依存はない

## 銀行からのお知らせ（packs/notices）

行員が出したお知らせを、利用者画面でねこが吹き出しで知らせる。キャンペーン（条件を満たすと特典が自動入金）はまだで、あとで足せる形にだけしてある。

| だれ | 場所 | できること |
|---|---|---|
| 行員 | `/admin/notices`（管理画面のメニュー「お知らせ」） | 出す・直す・掲載終了。種類（お知らせ / お願い / メンテナンス）、タイトル・本文、掲載期間（終了は空なら終わりなし）、対象（全員 / 選んだ利用者）、重要 |
| 利用者 | 利用者画面のどのページにも | ページの頭にねこの吹き出し（最大3件、ほかは「ほかに N 件」）、メニューの「お知らせ」に未読のバッジ |
| 利用者 | `/notices`・`/notices/:id` | 一覧（未読は NEW）と本文。開くと既読 |

- **見えるもの**: いま掲載中（`starts_at <= 今 < ends_at`）で、自分が対象のものだけ。期間外・対象外は一覧に出ず、開いても閉じても 404
- **既読と「閉じる」**: 利用者ごとに `notice_receipts`（`read_at` / `dismissed_at`）。ふつうのお知らせは未読のあいだ吹き出しに出て、開くか × で消える。
  **重要なものは開いて既読になっても、× で閉じるまで吹き出しに出し続ける**（本文のページにも「読んだにゃ（吹き出しを閉じる）」）
- **掲載終了**は消さずに `ends_at` を今にする（だれが読んだかは残る）。始まる前のものを終えたら、始まりも今にする
- **ライブ更新**: `Notices::Board` が保存したら `Notices::RefreshJob` が Turbo の refresh（morph）を `"notices"`（全員）に送る。
  掲載の始まり・終わりが先なら、その時刻にも送る（`set(wait_until:)`。Solid Queue）。既読・閉じたは `[user, :notices]` に送ってほかのタブにも映す。
  refresh は「取り直して」という合図だけで中身を運ばないので、対象外の人に届いても何も漏れない
- **動き**: morph で新しく入った吹き出しだけが「ぽよん」と出る（CSS。すでにある要素は morph で残るので動き直さない）。
  ねこが跳ねてトースト（「銀行からお知らせが届いたにゃ！」）は Stimulus の `notices--inbox`。未読のバッジはぴょこぴょこ。
  `prefers-reduced-motion` なら跳ねる・ぽよん・バッジの動きを止める（トーストは出す）
- **Turbo の prefetch に注意**: Turbo 8 はリンクにホバーすると先読みする。「開いたら既読」の GET が先読みされて、マウスを乗せただけで既読になった。
  吹き出しと一覧に `data-turbo-prefetch="false"` を付け、サーバーでも `X-Sec-Purpose: prefetch` のときは既読にしない（応答は `no-store`）

### パッケージの境目

- customer からは `helper Notices::InboxHelper` して、レイアウトで `<%= notices_inbox %>` を1回呼ぶだけ。中で `content_for` の
  `:head`（CSS）・`:nav`（バッジ）・`:page_top`（吹き出し。packs/ui の `layouts/application` が main の頭に出す）を入れる。
  ヘルパーの定数が「notices を使っている」しるしになって、packwerk で customer → notices の依存が見える
- 行員の画面も packs/notices の中（`Notices::Admin::`、`/admin/notices`）。商店の管理を `/shop/admin` に置いたのと同じ理由で、
  admin が notices に依存しないよう、管理画面のメニューはリンク（ルート名）1つだけ
- CSS と Stimulus もパックの中（`app/assets/stylesheets/notices`・`app/javascript/controllers/notices`）。読み込み先は
  `packs/notices/config/initializers/assets.rb`、JS の pin はルートの `config/importmap.rb`（`pin_all_from … under: "controllers/notices"`）

### イベントソーシングにしなかった理由

お知らせは行員が書いて直す「文面」で、お金も業務ルール（不変条件）もなく、直した履歴をたどる必要もない。読む画面と書く画面のモデルも同じ。
RES の集約にすると、読み取りモデル・プロジェクション・作り直しまで要るのに、得るものがない。既読も利用者ごとの小さな状態で、ふつうの行で足りる。

キャンペーン（TODO の P の後半・L）で要るのは「振込が完了した → 条件を満たした → 特典を入金 → お祝いを知らせる」という**連鎖**で、
そこはイベント（銀行の `TransferCompleted` などを購読し、correlation / causation でたどる）にする。ただし連鎖の正は**キャンペーンのパック**が持ち、
お知らせはその最後に `Notices::Board#post(kind: …, users: [user])` で「特典が届いたにゃ」を出すだけ。お知らせ側はイベントを知らなくてよい。

キャンペーンを足すとき:

- `Notice::KINDS` に `"campaign"` を足す（ラベルと絵文字。CSS は `.notice-kind-campaign` の色）
- キャンペーンのパック（例: `packs/campaigns`、依存は banking・notices）が条件と特典を持ち、銀行のイベントを購読して `Banking::Bank` で入金し、`Notices::Board` で知らせる
- お知らせから「参加する」ボタンなどへつなぐなら、そのときに `notices` にリンク先の列を足す

## Hotwire で使っているもの

| 機能 | 場所 |
|---|---|
| Turbo Frame（遅延読み込み・Frame 内の画面遷移） | 口座ページの入出金・振込フォーム（入力 → 確認 → 確定）。利用者画面は振込だけ |
| Turbo Frame + `data-turbo-action="advance"` | 時点指定の残高（URL の `?date=` も進む） |
| Turbo 8 の refresh（morph） | `turbo_refreshes_with` + `turbo_stream_from`。ほかのプロセスからの入出金も即反映 |
| Stimulus | `amount_controller`（+10 / +50 ボタン）、`autosubmit_controller`（日付を変えたら送信） |
| 利用者画面の動き（Stimulus + CSS、外部ライブラリなし） | `count_up_controller`（残高のカウントアップ。morph で値が変わると前の値から数える）、`arrival_controller`（morph で届いた通帳の行をふわっと出す）、`transfer_status_controller` → `celebrate_controller`（振込完了・入金で紙吹雪とトースト）。`prefers-reduced-motion` なら止める |
| View Transitions | 利用者画面だけ `<meta name="view-transition">`。一覧と口座ページで残高がつながる |
| Turbo の refresh（morph）+ Solid Queue の予約 | 銀行からのお知らせ。出した・直した・掲載の始まり / 終わりの時刻に `Notices::RefreshJob`。新しい吹き出しだけ CSS で出る。`data-turbo-prefetch="false"`（開くと既読のため） |

## MCP（packs/mcp）

Claude などの MCP クライアントから銀行を使うための入口。公式の Ruby SDK（`mcp` gem）で、
Rails の同じプロセスの中に Streamable HTTP のエンドポイント `/mcp` を置いている
（stateless・JSON で返す）。同じプロセスなので、振込の入金ジョブや画面のライブ更新もそのまま効く。

| ツール | 中身 |
|---|---|
| `list_accounts` | 口座一覧（口座番号・名義・状態・残高） |
| `get_account` | 残高と通帳（新しいほうから `limit` 件） |
| `balance_at` | ある日の終わり時点の残高。起算日基準（`as_of`）と記帳日基準（`as_at`）の両方 |
| `list_transfers` / `get_transfer` | 振込の一覧・状態（処理中 / 完了 / 組戻し） |
| `deposit` / `withdraw` / `transfer` | 入金・出金・振込。**既定はドライラン**。`confirm: true` のときだけ書き込む |

- 書き込みは `Banking::Bank`（actor `"mcp"`）だけを通す。ドライランでは残高の変化・警告・発生するイベントを返す
- サーバーの instructions とツールの説明で「ドライランを見せて OK をもらってから `confirm: true`」と指示している
- localhost 以外からのリクエストは 403。Host / Origin の検査（DNS リバインディング対策）は SDK が行う
- トークン認証（任意）: 環境変数 `CHURU_MCP_TOKEN` か credentials の `mcp.token` を設定すると、
  `Authorization: Bearer <トークン>` が必須になる（設定しなければ localhost だけで受け付ける）

Claude Code への登録の例（サーバーを `bin/dev` で起動しておく）:

```bash
claude mcp add --transport http churu-bank http://localhost:3000/mcp
# トークンを設定したとき
claude mcp add --transport http churu-bank http://localhost:3000/mcp --header "Authorization: Bearer ${CHURU_MCP_TOKEN}"
```

curl で試す:

```bash
curl -s localhost:3000/mcp -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_account","arguments":{"account_number":"0000001"}}}'
```

## TODO

| # | やること | 先に必要 | 主な場所 |
|---|---|---|---|
| ~~A~~ | ~~packwerk 導入、銀行を `packs/banking` へ~~（済） | | |
| ~~B~~ | ~~認証（Rails 8 の `generate authentication`）、ユーザーと口座のひも付け~~（済） | | `packs/identity` |
| ~~C~~ | ~~管理画面（行員）と利用者画面（口座の持ち主）を分ける~~（済） | B | `packs/admin`・`packs/customer` |
| ~~D~~ | ~~2つめのドメイン「ちゅ〜る商店」: 商品・在庫・注文。支払いは `Banking::Bank` 経由、在庫切れなら返金~~（済） | | `packs/shop` |
| ~~E~~ | ~~MCP（`/mcp`、HTTP）: 残高照会・明細・振込（ドライラン → 確定）~~（済） | | `packs/mcp` |
| ~~F~~ | ~~利息（Solid Queue の recurring で日次計算）~~（済。画面は O） | | `packs/banking` |
| ~~G~~ | ~~取消（逆仕訳）~~（済。画面は O） | | `packs/banking` |
| ~~H~~ | ~~読み取りモデルの作り直し（`bin/rails churu:rebuild_projections`）~~（済） | | `packs/banking` |
| I | GitHub（public）と CI | | `.github/` |
| ~~J~~ | ~~Zingiber から銀行の MCP を使う~~（やらない。2026-10-21 決定） | E | Zingiber 側 |
| K | Ractor で住民の生活シミュレーション（働く・買う・振り込む）。Ractor は行動を決めるだけで、書き込みはメインから公開 API 経由 | D | `packs/simulation` |
| L | イベントからイベントが連鎖する処理（例: 振込完了 → ポイント付与 → ランクアップ → お祝い通知）。correlation / causation で連鎖を辿れるように | D あたり | 新しいパック |
| ~~M~~ | ~~利用者画面はとにかくかわいく。アニメーション（残高のカウントアップ、入金でふわっと、振込完了のお祝い）。reduced-motion に配慮~~（済） | C | `packs/customer` |
| ~~N~~ | ~~商店を認証につなぐ: 購入者はログイン中の利用者の口座、商品・在庫の管理は行員だけ。画面の共通部品（ヘルパー・レイアウト）を UI 用のパックへ~~（済） | B, D | `packs/shop`・`packs/ui` |
| ~~O~~ | ~~管理画面に取消・組戻し・利息の手動実行のボタン~~（済。「管理画面での取消・組戻し・利息」） | F, G | `packs/admin` |
| P | 利用者画面に銀行からのお知らせ・お願い・キャンペーン（**お知らせ・お願いは済**。キャンペーン = 条件を満たすと特典が自動入金、は未） | C, N（キャンペーンは L） | `packs/notices`（キャンペーンは新しいパック） |
| Q | 行員の権限を本物の銀行に寄せる。**Q0（先に）行員と利用者の完全な分離**: 別のモデル・テーブル・ログイン画面・セッション・Cookie、Action Cable も別、actor は `staff:` / `customer:`、パックも `staff_identity` / `customer_identity` に分ける。Q1 窓口取引: 出金は利用者の「出金依頼」があるときだけ行員が処理（入金は現金持ち込みとして行員のみ）。Q2 二人承認: 取消・組戻し・凍結の解除は「申請 → 別の行員が承認 → 実行」。Q3 振込の差し止め: 予約振込と高額振込の保留を足し、実行前なら利用者は取消・行員は差し止めできる | O | `packs/banking`・`packs/admin`・`packs/customer`（承認は新しいパック） |
| R | 日本語のイベントビューア（RES Browser の代わり）: イベント名・ストリーム名を日本語に、中身を表で、correlation / causation の連鎖を図で。管理画面の中、行員だけ | Q0 | 新しいパック（例 `packs/event_viewer`） |

並行の進め方（フェーズ1）: B+C / D / E→J / F+G+H を別々に進められる。
各自 `jj workspace add ../churu-bank-<名前>` で作業ディレクトリを分け、`bin/dev -p 300X` でポートも分ける
（DB は `storage/` 以下なので、作業ディレクトリごとに別になる）。
`config/routes.rb`・`db/schema.rb` は複数から触るので、最後にまとめてマージする。
