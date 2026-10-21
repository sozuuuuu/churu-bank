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

## パッケージ（packwerk）

| パッケージ | 中身 | 依存してよい先 |
|---|---|---|
| `.`（ルート） | レイアウト・JS（Stimulus）・CSS・ヘルパー、画面へのライブ更新（`BroadcastRefreshJob`）、イベントストア本体 | platform, banking, identity |
| `packs/admin` | 管理画面 `/admin`（`Admin::`）。全口座の開設・入出金・振込・凍結、振込一覧。管理者だけ | platform, banking, identity |
| `packs/customer` | 利用者画面 `/`（`Customer::`）。自分の口座の一覧・通帳・時点残高、自分の口座からの振込 | platform, banking, identity |
| `packs/identity` | ログイン（Rails 8 の `generate authentication`）、`User#admin`、利用者と口座のひも付け（`account_ownerships`）。外から使えるのは `app/public`（`User` / `Current` / `Authentication`） | platform |
| `packs/banking` | 銀行ドメイン。外から使えるのは `app/public` だけ（`Banking::Bank` ほか） | platform |
| `packs/shop` | ちゅ〜る商店（商品・在庫・注文）と `/shop` の画面。外から使えるのは `app/public` だけ（`Shop::Store` ほか） | platform, banking |
| `packs/mcp` | MCP サーバー（`/mcp`）。ツールは `app/mcp/churu_mcp/tools` | platform, banking |
| `packs/platform` | `ApplicationRecord` / `ApplicationJob` / `ApplicationController` などの土台 | なし |

- `bin/packwerk check` で、依存（`enforce_dependencies`）と非公開の参照（`enforce_privacy`、packwerk-extensions）を検査する
- 各パックは自分の `config/initializers` で自分のイベント購読だけを書く。イベントストア本体はルート
- パックのテストは `packs/<名前>/test`。`bin/test` でまとめて流れる
- ルーティングも各パックの `config/routes/<名前>.rb` に書き、`config/routes.rb` から `draw :<名前>` で読む
- admin と customer は互いに依存しない。銀行は `User` を知らない（口座番号だけでつながる）

## 認証と権限

- ログインは `packs/identity`（Rails 8 の `generate authentication` がもと。パスワード再設定は入れていない）。
  画面のパックのベースコントローラ（`Admin::ApplicationController` / `Customer::ApplicationController`）で
  `Authentication` を include する
- 管理画面は `User#admin` だけ。そうでなければ 404（管理画面があることも見せない）。`/res` もルーティングの制約で管理者だけ
- 利用者画面は `account_ownerships` でひも付いた口座だけ。他人の口座は口座ページ・時点残高・振込とも 404。
  入出金と凍結は行員だけ。振込先には全口座（解約済みを除く）を選べる
- 利用者画面は見た目も別（ねこ・ちゅ〜るのテーマ、`packs/customer/app/assets/stylesheets/customer/theme.css`）。`body.customer` の下だけに効き、管理画面は今の見た目のまま
- だれの操作かは、イベントの metadata の actor に `admin:<メール>` / `customer:<メール>` で残る
- Action Cable もログインが必要（`ApplicationCable::Connection`）。購読できるのは画面に埋め込まれた署名つきのストリームだけ

### packwerk の気づき（商店を作って）

- 商店は銀行の公開 API（`Bank` / `Events` / 例外 / 読み取りモデル）だけで作れた。プロセスマネージャは
  銀行のイベント（`TransferCompleted` / `TransferFailed`）を購読するので、銀行側の変更はいらない
- 商店のテストで銀行の非公開ジョブ（`Transfers::SettleJob`）だけを流そうとして privacy 違反になった。
  `perform_enqueued_jobs(except: Shop::PaymentJob)` のように「自分のジョブ以外」と書けば済む
- 画面の土台（`ApplicationController`・レイアウト・`churu` などのヘルパー・`account_path`）はルートにあり、
  パックからは依存できない。商店は `ActionController::Base` から直接作り、レイアウトとヘルパーは名前で借りている。
  定数ではないので packwerk には見えない依存。画面の共通部品は `packs/platform`（か UI 用のパック）に移すのがよさそう
  （商店は認証より前に作ったので、ログイン・利用者の口座とのつなぎ込みは TODO の N）

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
- 購入者はいまは画面で口座を選ぶだけ（`Shop::ApplicationController#current_buyer`）。認証ができたら差し替える
- 開発用の商品は `bin/rails db:seed`（商店の口座も開く）

## Hotwire で使っているもの

| 機能 | 場所 |
|---|---|
| Turbo Frame（遅延読み込み・Frame 内の画面遷移） | 口座ページの入出金・振込フォーム（入力 → 確認 → 確定）。利用者画面は振込だけ |
| Turbo Frame + `data-turbo-action="advance"` | 時点指定の残高（URL の `?date=` も進む） |
| Turbo 8 の refresh（morph） | `turbo_refreshes_with` + `turbo_stream_from`。ほかのプロセスからの入出金も即反映 |
| Stimulus | `amount_controller`（+10 / +50 ボタン）、`autosubmit_controller`（日付を変えたら送信） |
| 利用者画面の動き（Stimulus + CSS、外部ライブラリなし） | `count_up_controller`（残高のカウントアップ。morph で値が変わると前の値から数える）、`arrival_controller`（morph で届いた通帳の行をふわっと出す）、`transfer_status_controller` → `celebrate_controller`（振込完了・入金で紙吹雪とトースト）。`prefers-reduced-motion` なら止める |
| View Transitions | 利用者画面だけ `<meta name="view-transition">`。一覧と口座ページで残高がつながる |

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
| ~~F~~ | ~~利息（Solid Queue の recurring で日次計算）~~（済。画面は未） | | `packs/banking` |
| ~~G~~ | ~~取消（逆仕訳）~~（済。画面は未: 通帳の「取消」・振込の「組戻し」ボタン） | | `packs/banking` |
| ~~H~~ | ~~読み取りモデルの作り直し（`bin/rails churu:rebuild_projections`）~~（済） | | `packs/banking` |
| I | GitHub（public）と CI | | `.github/` |
| ~~J~~ | ~~Zingiber から銀行の MCP を使う~~（やらない。2026-10-21 決定） | E | Zingiber 側 |
| K | Ractor で住民の生活シミュレーション（働く・買う・振り込む）。Ractor は行動を決めるだけで、書き込みはメインから公開 API 経由 | D | `packs/simulation` |
| L | イベントからイベントが連鎖する処理（例: 振込完了 → ポイント付与 → ランクアップ → お祝い通知）。correlation / causation で連鎖を辿れるように | D あたり | 新しいパック |
| ~~M~~ | ~~利用者画面はとにかくかわいく。アニメーション（残高のカウントアップ、入金でふわっと、振込完了のお祝い）。reduced-motion に配慮~~（済） | C | `packs/customer` |
| N | 商店を認証につなぐ: 購入者はログイン中の利用者の口座、商品・在庫の管理は行員だけ。画面の共通部品（ヘルパー・レイアウト）を UI 用のパックへ | B, D | `packs/shop`・`packs/platform` |
| O | 管理画面に取消・組戻し・利息の手動実行のボタン（API は「画面から使う Banking::Bank の API」） | F, G | `packs/admin` |

並行の進め方（フェーズ1）: B+C / D / E→J / F+G+H を別々に進められる。
各自 `jj workspace add ../churu-bank-<名前>` で作業ディレクトリを分け、`bin/dev -p 300X` でポートも分ける
（DB は `storage/` 以下なので、作業ディレクトリごとに別になる）。
`config/routes.rb`・`db/schema.rb` は複数から触るので、最後にまとめてマージする。
