# ちゅーる銀行 🐟

通貨「ちゅ〜る」の銀行ごっこ。Rails 8 + Rails Event Store（RES）で、イベントソーシングと
Hotwire・Solid Queue・Solid Cable など Rails 標準の機能を一通り使ってみるためのアプリ。

## 起動

```bash
bin/rails db:prepare
bin/dev            # http://localhost:3000 （Solid Queue のワーカーも Puma の中で動く）
bin/test           # ルートとすべてのパックのテスト
bin/ci             # rubocop / packwerk / brakeman / テスト を全部
```

- 環境: WSL の Ubuntu 24.04、Ruby は mise（`mise.toml`）、バージョン管理は jj
- `/res` … RES Browser（イベントストアの中身を見る）

## パッケージ（packwerk）

| パッケージ | 中身 | 依存してよい先 |
|---|---|---|
| `.`（ルート） | 画面（いまは管理画面だけ）、画面へのライブ更新、イベントストア本体 | platform, banking |
| `packs/banking` | 銀行ドメイン。外から使えるのは `app/public` だけ（`Banking::Bank` ほか） | platform |
| `packs/mcp` | MCP サーバー（`/mcp`）。ツールは `app/mcp/churu_mcp/tools` | platform, banking |
| `packs/platform` | `ApplicationRecord` / `ApplicationJob` などの土台 | なし |

- `bin/packwerk check` で、依存（`enforce_dependencies`）と非公開の参照（`enforce_privacy`、packwerk-extensions）を検査する
- 各パックは自分の `config/initializers` で自分のイベント購読だけを書く。イベントストア本体はルート
- パックのテストは `packs/<名前>/test`。`bin/test` でまとめて流れる

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
| Turbo Frame（遅延読み込み・Frame 内の画面遷移） | 口座ページの入出金フォーム（入力 → 確認 → 確定） |
| Turbo Frame + `data-turbo-action="advance"` | 時点指定の残高（URL の `?date=` も進む） |
| Turbo 8 の refresh（morph） | `turbo_refreshes_with` + `turbo_stream_from`。ほかのプロセスからの入出金も即反映 |
| Stimulus | `amount_controller`（+10 / +50 ボタン）、`autosubmit_controller`（日付を変えたら送信） |

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
| B | 認証（Rails 8 の `generate authentication`）、ユーザーと口座のひも付け | | `packs/identity`（予定） |
| C | 管理画面（行員）と利用者画面（口座の持ち主）を分ける | B | `packs/admin`・`packs/customer` |
| D | 2つめのドメイン「ちゅ〜る商店」: 商品・在庫・注文。支払いは `Banking::Bank` 経由、在庫切れなら返金 | | `packs/shop` |
| ~~E~~ | ~~MCP（`/mcp`、HTTP）: 残高照会・明細・振込（ドライラン → 確定）~~（済） | | `packs/mcp` |
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
