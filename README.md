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

## Hotwire で使っているもの

| 機能 | 場所 |
|---|---|
| Turbo Frame（遅延読み込み・Frame 内の画面遷移） | 口座ページの入出金・振込フォーム（入力 → 確認 → 確定）。利用者画面は振込だけ |
| Turbo Frame + `data-turbo-action="advance"` | 時点指定の残高（URL の `?date=` も進む） |
| Turbo 8 の refresh（morph） | `turbo_refreshes_with` + `turbo_stream_from`。ほかのプロセスからの入出金も即反映 |
| Stimulus | `amount_controller`（+10 / +50 ボタン）、`autosubmit_controller`（日付を変えたら送信） |
| 利用者画面の動き（Stimulus + CSS、外部ライブラリなし） | `count_up_controller`（残高のカウントアップ。morph で値が変わると前の値から数える）、`arrival_controller`（morph で届いた通帳の行をふわっと出す）、`transfer_status_controller` → `celebrate_controller`（振込完了・入金で紙吹雪とトースト）。`prefers-reduced-motion` なら止める |
| View Transitions | 利用者画面だけ `<meta name="view-transition">`。一覧と口座ページで残高がつながる |

## TODO

| # | やること | 先に必要 | 主な場所 |
|---|---|---|---|
| ~~A~~ | ~~packwerk 導入、銀行を `packs/banking` へ~~（済） | | |
| ~~B~~ | ~~認証（Rails 8 の `generate authentication`）、ユーザーと口座のひも付け~~（済） | | `packs/identity` |
| ~~C~~ | ~~管理画面（行員）と利用者画面（口座の持ち主）を分ける~~（済） | B | `packs/admin`・`packs/customer` |
| D | 2つめのドメイン「ちゅ〜る商店」: 商品・在庫・注文。支払いは `Banking::Bank` 経由、在庫切れなら返金 | | `packs/shop` |
| E | MCP（`/mcp`、HTTP）: 残高照会・明細・振込（ドライラン → 確定） | | `packs/mcp` |
| F | 利息（Solid Queue の recurring で日次計算） | | `packs/banking` |
| G | 取消（逆仕訳） | | `packs/banking` |
| H | 読み取りモデルの作り直し（`bin/rails churu:rebuild_projections`） | | `packs/banking` |
| I | GitHub（private）と CI | | `.github/` |
| J | Zingiber から銀行の MCP を使う | E | Zingiber 側 |
| K | Ractor で住民の生活シミュレーション（働く・買う・振り込む）。Ractor は行動を決めるだけで、書き込みはメインから公開 API 経由 | D | `packs/simulation` |

並行の進め方（フェーズ1）: B+C / D / E→J / F+G+H を別々に進められる。
各自 `jj workspace add ../churu-bank-<名前>` で作業ディレクトリを分け、`bin/dev -p 300X` でポートも分ける
（DB は `storage/` 以下なので、作業ディレクトリごとに別になる）。
`config/routes.rb`・`db/schema.rb` は複数から触るので、最後にまとめてマージする。
