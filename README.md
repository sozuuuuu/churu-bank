# ちゅーる銀行 🐟

通貨「ちゅ〜る」の銀行ごっこ。Rails 8 + Rails Event Store（RES）で、イベントソーシングと
Hotwire・Solid Queue・Solid Cable など Rails 標準の機能を一通り使ってみるためのアプリ。

## 起動

```bash
bin/rails db:prepare   # 開発用の行員・利用者・口座も入る（db/seeds.rb）
bin/dev            # http://localhost:3000 （Solid Queue のワーカーも Puma の中で動く）
bin/test           # ルートとすべてのパックのテスト
bin/ci             # rubocop / packwerk / brakeman / テスト を全部
```

- 環境: WSL の Ubuntu 24.04、Ruby は mise（`mise.toml`）、バージョン管理は jj
- ログイン: 開発用のアカウントは `db/seeds.rb`（行員の たま・くろ と、利用者のオルカ・ジンジベル・ミケ）。
  **行員と利用者はアカウントもログイン画面も別**。どちらも学習用なのでパスワードなしで、ドロップダウンで選んで入るだけ:
  行員は `/admin/session/new`、利用者は `/session/new`
- `/` … 利用者画面（自分の口座だけ。`/events` … わたしの出来事）、`/admin` … 管理画面（行員だけ）。`/admin/counter` … 窓口（出金依頼の処理）、
  `/admin/approvals` … 承認待ち（二人承認）
- `/admin/events` … イベントビューア（出来事を日本語で・図で見る。行員だけ。眺める出来事は `bin/rails churu:demo_events` で起こせる）。
  `/res` … RES Browser（イベントストアの中身をそのまま見る英語の画面。行員だけ）
- `/notices` … 銀行からのお知らせ（利用者）、`/admin/notices` … お知らせを出す・直す・掲載終了（行員）
- `/shop` … ちゅ〜る商店（利用者の買い物）、`/shop/admin` … 商品と在庫の管理（行員）
- `/counter` … 窓口の番号札とチャット（利用者）、`/admin/counter/queue` … 整理券の列と窓口チャット（行員）

## パッケージ（packwerk）

| パッケージ | 中身 | 依存してよい先 |
|---|---|---|
| `.`（ルート） | JS（Stimulus）・CSS、画面へのライブ更新（`BroadcastRefreshJob`）、Action Cable の接続（`ApplicationCable::Connection`。行員か利用者か）、イベントストア本体 | platform, banking, staff_identity, customer_identity, customer_registry |
| `packs/staff_identity` | **行員のログイン**（`/admin/session`）。`Staff` とセッション、`StaffAuthentication`・`StaffHelper`・`StaffStreamsChannel` を公開 | platform |
| `packs/customer_identity` | **利用者のログイン**（`/session`、ねこテーマ）。セッション、`CustomerAuthentication`・`CustomerHelper`・`CustomerStreamsChannel` を公開 | platform, customer_registry, ui |
| `packs/customer_registry` | **顧客台帳**: 利用者 `Customer` と口座のひも付け（`account_ownerships`）。ログインのしくみは持たない。公開は `Customer` だけ | platform |
| `packs/admin` | 管理画面 `/admin`（`Admin::`）。全口座の開設・入金（現金の持ち込み）・振込・凍結、窓口（出金依頼の処理）、振込一覧、取消・組戻し・凍結の解除の申請と承認待ち、利息。行員だけ | platform, banking, approvals, staff_identity, customer_registry, ui |
| `packs/customer` | 利用者画面 `/`（`Netbank::`）。自分の口座の一覧・通帳・時点残高、自分の口座からの振込と出金の依頼。お知らせはレイアウトで `notices_inbox` を1回呼ぶだけ。わたしの出来事 `/events`（`MyEvents::`。自分の口座にかかわるイベントだけ） | platform, banking, customer_identity, customer_registry, ui, notices, event_lens, shop |
| `packs/banking` | 銀行ドメイン（口座・振込・出金依頼）。外から使えるのは `app/public` だけ（`Banking::Bank` ほか） | platform |
| `packs/approvals` | **二人承認**: 取消・組戻し・凍結の解除の「申請 → 別の行員が承認 → 実行」（却下・取り下げ）。外から使えるのは `app/public`（`Approvals::Desk` / `Approvals::Events` / `ApprovalRequest`） | platform, banking |
| `packs/shop` | ちゅ〜る商店（商品・在庫・注文）と、利用者の買い物の画面 `/shop`。外から使えるのは `app/public` だけ（`Shop::Store` ほか） | platform, banking, customer_identity, ui |
| `packs/shop_admin` | 商品と在庫の管理 `/shop/admin`（`ShopAdmin::`）。商品の登録・値段・入荷・商店の口座を開く、注文を全員分見る。行員だけ | platform, banking, shop, staff_identity, ui |
| `packs/ui` | 画面の共通部品: 外枠のレイアウト（`layouts/application`。`content_for :nav` / `:account` / `:home_path` / `:page_top` で差し込む）、ねこテーマ（`layouts/cat` と `ui/cat.css`、画面下のセリフ窓 `ui/_serif`）、`Ui::FormatHelper`（`churu` / `jp_date` / `jp_time`）、`Ui::ThemeHelper`（線画のアイコン・表情4種のねこ・ねこのセリフ）。だれがログインしているかは知らない | platform |
| `packs/notices` | 銀行からのお知らせ・お願い・メンテナンス（ふつうの ActiveRecord）と、利用者の `/notices`・ねこの吹き出し。外から使えるのは `app/public`（`Notices::InboxHelper` / `Notices::Board` / `Notice`） | platform, customer_identity, customer_registry, ui |
| `packs/notices_admin` | お知らせの管理 `/admin/notices`（`NoticesAdmin::`）。出す・直す・掲載終了。行員だけ | platform, notices, staff_identity, customer_registry, ui |
| `packs/counter` | **窓口の整理券と窓口チャット**（ふつうの表）と、Action Cable のチャンネル（`Counter::TicketChannel`・`ChatChannel`・`QueueChannel`）、利用者の画面 `/counter`。外から使えるのは `app/public`（`Counter::Desk` / `CounterTicket` / `CounterMessage`） | platform, customer_identity, customer_registry, ui |
| `packs/counter_admin` | 整理券の列と窓口チャットの行員の画面 `/admin/counter/queue`（`CounterAdmin::`）。次の方・終わる、チャットの横に受付中の出金依頼。行員だけ | platform, counter, banking, staff_identity, customer_registry, ui |
| `packs/mcp` | MCP サーバー（`/mcp`）。ツールは `app/mcp/churu_mcp/tools` | platform, banking |
| `packs/event_viewer` | イベントビューア `/admin/events`（`EventViewer::`）。イベントを日本語で: 一覧と生中継・つながりの図・タイムマシン・レーン図。読むだけ。行員だけ | platform, event_lens, banking, shop, approvals, staff_identity, customer_registry, ui |
| `packs/event_lens` | イベントを読み解く部品（`EventLens::`）: 日本語の名前・つながりの図・タイムマシン・表示の部品・Stimulus・CSS。行員の画面と利用者の画面が共通で使う。どちらのログインにも依存しない | platform, banking, shop, approvals, ui |
| `packs/platform` | `ApplicationRecord` / `ApplicationJob` / `ApplicationController` などの土台 | なし |

- `bin/packwerk check` で、依存（`enforce_dependencies`）と非公開の参照（`enforce_privacy`、packwerk-extensions）を検査する
- 各パックは自分の `config/initializers` で自分のイベント購読だけを書く。イベントストア本体はルート
- パックのテストは `packs/<名前>/test`。`bin/test` でまとめて流れる
- ルーティングも各パックの `config/routes/<名前>.rb` に書き、`config/routes.rb` から `draw :<名前>` で読む
- admin と customer は互いに依存しない。銀行は `Customer` も `Staff` も知らない（口座番号だけでつながる）
- **画面のパックは staff_identity か customer_identity の片方にだけ依存する**（行員の画面: admin / shop_admin / notices_admin / event_viewer、
  利用者の画面: customer / shop / notices）。宣言していない側の `StaffAuthentication` / `CustomerAuthentication` を使えば
  `bin/packwerk check` が依存違反にする。両方を宣言しないといけなくなったら、画面を分けてパックも分けるしるし（shop_admin / notices_admin がそう）
- 画面のパック（admin / customer / shop など）は、ベースコントローラで `helper Ui::FormatHelper` して packs/ui に依存する。
  レイアウトはテンプレート名（`render template: "layouts/application"` / `"layouts/cat"`）で使うので packwerk には見えないが、
  `Ui::FormatHelper` の参照が「ui を使っている」しるしになり、`bin/packwerk check` で依存の宣言漏れが見つかる

## 認証と権限

本物の銀行で、行員の業務システムとネットバンキングが別物なのと同じく、**行員と利用者は完全に分けている**（TODO の Q0）。

| | 行員 | 利用者 |
|---|---|---|
| モデル・テーブル | `Staff`（`staffs`）・`staff_sessions` | `Customer`（`customers`、顧客台帳）・`customer_sessions` |
| パック | `packs/staff_identity` | `packs/customer_identity`（ログイン）＋ `packs/customer_registry`（台帳） |
| ログイン画面 | `/admin/session/new`（管理画面と同じ見た目。行員をドロップダウンで選ぶだけ） | `/session/new`（ねこテーマ。**学習用なのでパスワードなし**: 利用者をドロップダウンで選んで入る。パスワードの列と検証は残してあるが使わない） |
| セッションの Cookie | `staff_session_id` | `customer_session_id` |
| ベースコントローラで include | `StaffAuthentication`（`current_staff`） | `CustomerAuthentication`（`current_customer`） |
| ライブ更新の購読 | `staff_stream_from` → `StaffStreamsChannel` | `customer_stream_from` → `CustomerStreamsChannel` |
| イベントの actor | `staff:<id>` | `customer:<id>` |

- **片方でログインしても、もう片方の画面には入れない**。行員の画面に行員のログインなしで来たら行員のログイン画面へ、
  利用者の画面に利用者のログインなしで来たら利用者のログイン画面へ飛ばす。利用者の画面には行員の画面へのリンクを出さない。
  `/res` はルーティングの制約（`StaffAuthentication::Constraint`）で、行員でなければ 404
- 同じブラウザで両方にログインしていてもよい（Cookie が別）。ログアウトもそれぞれ。行員が客でもあるなら、利用者のアカウントを別に持つ
- **Cookie の署名も別**: Rails の署名つき Cookie は Cookie の名前ごとに署名が違う（メタデータの purpose）ので、
  行員の Cookie の値を `customer_session_id` に入れても通らない（id がたまたま同じでも）
- **Action Cable**: `ApplicationCable::Connection` が接続ごとに `current_staff` / `current_customer` を持つ（どちらもなければ拒否）。
  `StaffStreamsChannel` は行員の接続だけ、`CustomerStreamsChannel` は利用者の接続だけが購読でき、ストリーム名の署名の鍵もチャンネルごとに別
  （`Rails.application.message_verifier("staff_streams")` / `("customer_streams")`）。なので行員の画面に埋め込まれた名前（`"accounts"` 全口座など）を
  利用者が手に入れても購読できない。素の `Turbo::StreamsChannel`（`turbo_stream_from`）は購読を拒否する（`config/initializers/turbo_streams.rb`）。
  配信はどちらも `Turbo::StreamsChannel.broadcast_refresh_to` のまま（ストリームの中身は同じで、購読の入口だけが分かれている）
- **行員のログインは厳密にしない**（学習用）: パスワードをやめ、`/admin/session/new` のドロップダウンで行員を選んで「入る」だけ。
  二人承認を試すのに、たま・くろを切り替えやすくするため。切り替えると前の行員のセッションは消える。
  入ったあとは今までどおり行員のセッション（`staff_session_id`）で、利用者のセッションとは別のまま（`Staff` の `password_digest` は残っているが使わない）
- 利用者画面は `account_ownerships` でひも付いた口座だけ。他人の口座は口座ページ・時点残高・振込・出金の依頼とも 404。
  出金は依頼を出すだけ（行員が窓口で処理する）。入金と凍結は行員だけ。振込先には全口座（解約済みを除く）を選べる
- 行員は口座の開設のときに持ち主（利用者）を選んでひも付ける。台帳（`Customer`）は packs/customer_registry にあり、
  行員の画面（admin・notices_admin）はここに依存するが、利用者のログイン（customer_identity）には依存しない
- 利用者画面は見た目も別（日本アニメ的 kawaii のねこテーマ、`packs/ui/app/assets/stylesheets/ui/cat.css`。`layouts/cat` が読み込む。「利用者画面の見た目」の節）。`body.cat-theme` の下だけに効き、管理画面は今の見た目のまま
- 商店の買い物（`/shop`）は利用者のログイン、商品と在庫の管理（`/shop/admin`）は行員のログイン。「ちゅ〜る商店」の節を参照
- だれの操作かは、イベントの metadata の actor に `staff:<id>` / `customer:<id>` で残る（メールアドレスは変わりうるので id）。
  Q0 より前のイベントは `admin:<メール>` / `customer:<メール>` / `shop:<メール>` のまま（過去のイベントは書き換えない）

### 行員の権限: 窓口取引と二人承認（TODO の Q1・Q2）

いままでは行員が一人で、利用者の口座から自由に出金・取消・組戻し・凍結の解除ができた。本物の銀行に寄せて、
**出金は利用者の依頼があるときだけ**、**お金を戻す・止めを外す操作は二人の行員で**にした。

```
Q1 窓口取引（ストリーム WithdrawalRequest$<依頼ID>）
  利用者  Bank#request_withdrawal … WithdrawalRequested（受付中。お金はまだ動かない）
          └ 処理の前なら Bank#cancel_withdrawal … WithdrawalRequestCancelled（取消済み）
  行員    窓口 /admin/counter
          ├ 出金する Bank#process_withdrawal … Account$ MoneyWithdrawn（data に request_id）→ WithdrawalRequestProcessed（出金済み）
          └ 断る    Bank#reject_withdrawal（理由は必須）… WithdrawalRequestRejected（お断り）

Q2 二人承認（ストリーム Approval$<申請ID>、packs/approvals）
  行員A  Approvals::Desk#request_reversal / request_transfer_reversal / request_unfreeze … ApprovalRequested（承認待ち）
          └ A 本人は取り下げだけ … ApprovalWithdrawn
  行員B  承認待ち /admin/approvals
          ├ 承認 Desk#approve … ApprovalGranted → 銀行のイベント（DepositReversed など）→ ApprovalExecuted（実行済み）を1トランザクションで
          └ 却下 Desk#reject（理由は必須）… ApprovalRejected（銀行は何も変わらない）
```

| 決めたこと | 中身 |
|---|---|
| 依頼なしの出金 | **入口をなくした**。`Bank#withdraw` を消し、出金は `process_withdrawal(依頼ID)` だけ。管理画面の口座ページは「入金（現金の持ち込み）」だけのフォームになり、出金は窓口へのリンク |
| 依頼のときのお金 | **押さえない**（凍結・残高が足りるかを確かめるだけ）。窓口で現金を渡すまでは口座のお金のまま（利息もつく）。処理するときに足りなければ `InsufficientFunds` で出金せず、依頼は受付中のまま（行員は断れる）。押さえないので、受付中の依頼の合計が残高を超えることはある |
| 二重の処理 | 依頼の状態（受付中でなければ `InvalidState`）と `WithdrawalRequest$` の expected_version。処理と利用者の取消が同時なら後の方が `ConcurrentModification` になり、出金も残らない |
| 出金依頼の置き場 | **銀行のパック**（`Banking::WithdrawalRequest`、読み取りモデル `WithdrawalRequest`）。依頼は口座のお金と同じ不変条件（凍結・残高）に乗っていて、処理は口座の MoneyWithdrawn と同じトランザクションで書く必要がある。別のパックにすると、そのパックが `Bank#withdraw` のような「依頼なしで出金できる入口」を銀行に開けさせることになり、「依頼があるときだけ」を銀行の中で守れない |
| 二人承認の対象 | 取消（入出金の逆仕訳）・振込の組戻し・凍結の解除。**凍結そのものは一人ですぐ**できるまま（不正の疑いで止めるのは急ぐ。止めすぎても解除で戻せる）。お金を戻す・止めを外すほうが、誤り・なりすましのときの害が大きい |
| 申請者と承認者 | 申請した本人は承認も却下もできない（取り下げだけ）。承認待ちの画面でも本人にはボタンを出さず、URL を直接たたいても `Approvals::Desk` が断る。却下は申請者以外ならだれでも（理由は必須） |
| 銀行の確かめ | 銀行は `reverse` / `reverse_transfer` / `unfreeze_account` に `approval: Banking::Bank::Approval(id, requested_by)` を求め、**承認がない・申請者 = 実行者（Bank の actor）なら `InvalidState`**。ドライラン（申請の確認画面の試算）だけは承認なしでよい。イベントの metadata に `approval_id`・`requested_by`・`approved_by` が残る（actor は承認した行員） |
| 二人承認の置き場 | **新しいパック `packs/approvals`**（依存は banking だけ）。二人承認は行員の業務の決まり（内部統制）で、お金の不変条件ではない。申請の一覧・却下・取り下げを銀行に入れると、銀行が行員の仕事の流れまで持つことになる。銀行は「承認があること」「別人であること」だけを確かめ、流れはこのパックが持つ。行員（`Staff`）は知らず、actor の文字列 `staff:<id>` で比べる |
| 承認と実行 | 承認したら**その場で実行**（承認と実行を分けない。「承認済みだが未実行」を作らない）。銀行で失敗したら（申請のあとで残高が減った等）全部戻り、申請は承認待ちのまま。申請のときにも銀行でドライランし、いまできない操作（取消済み・理由なしなど）は申請できない |
| 同じ対象 | 同じ通帳の行・振込・口座の解除の承認待ちは1つだけ（読み取りモデルの一意インデックス `status = 'pending'`）。却下・取り下げのあとはまた申請できる |
| だれが | 申請・承認・却下・取り下げはそれぞれ `Approval$<申請ID>` のイベントの actor。実行した銀行のイベントもこのストリームにリンクするので、RES Browser で「だれが申請し、だれが承認し、何が起きたか」を1か所で辿れる。出金依頼も `WithdrawalRequest$<依頼ID>` に MoneyWithdrawn をリンク |
| 画面のライブ更新 | 出金依頼のイベントは `BroadcastRefreshJob` が `"withdrawal_requests"`（窓口）と口座に、申請のイベントは `Approvals::RefreshJob` が `"approvals"`（承認待ち）と口座に refresh を送る。メニューの「窓口」「承認待ち」に件数のバッジ |
| MCP | `withdraw` をやめ、**`request_withdrawal`（依頼を出すだけ）** にした。MCP にはだれが使っているかの区別がない（actor は `mcp`）ので、行員の操作（処理・断る・承認）は出さない。入金（`deposit`）は今までどおり |

画面:

| だれ | 場所 | できること |
|---|---|---|
| 利用者 | 口座ページの「出金の依頼」 | 金額・メモ → 確認 → 「出金を依頼する」（Frame `withdrawal_request`）。最近の依頼の状態（受付中・出金済み・お断り（理由）・取消済み）、受付中なら「取り消す」 |
| 行員 | 窓口 `/admin/counter` | 受付中の依頼に「出金する」（確認 → 確定）・「断る」（理由 → 確認 → 確定）。Frame `counter`。最近の処理（だれが処理・お断り） |
| 行員 | 口座ページ | 入金（現金の持ち込み）。通帳の「取消」・「組戻し」は**申請**（確定で申請）。申請中の行は「承認待ち」。凍結中なら理由を書いて「凍結の解除を申請する」。この口座の承認待ちと出金依頼 |
| 行員 | 承認待ち `/admin/approvals` | 他人の申請に「承認する」（実行するとどうなるかの確認 → 承認して実行）・「却下する」（理由）。自分の申請は「取り下げる」だけ。最近の結果（申請者・承認／却下した人） |

読み取りモデルの作り直し: 出金依頼は `bin/rails churu:rebuild_projections` に入っている。二人承認は `bin/rails approvals:rebuild_projections`（パックが別なので別のタスク）。

### パックの分け方（Q0）

- **ログインは2つのパック**（staff_identity / customer_identity）。共通の「ログインのパック」を作らず、それぞれが Rails 8 の
  `generate authentication` の形を持つ。少し重複するが、片方に足した仕組み（たとえば行員だけの二人承認やアクセス制限）がもう片方に漏れない
- **顧客台帳（customer_registry）をログインから分けた**: 行員の画面も「利用者の一覧」「口座のひも付け」を使う（口座の開設・お知らせの対象）。
  台帳を customer_identity に置くと、行員の画面が利用者のログインのパックに依存できてしまい、packwerk で混ざりを止められない。
  本物の銀行でも、顧客の台帳（窓口で行員が引く）とネットバンキングのログインは別物
- **shop と notices は行員の画面を別のパックに出した**（shop_admin / notices_admin）。どちらも同じパックの中に行員の画面と利用者の画面があり、
  そのままだと1つのパックが両方のログインに依存する。packwerk の依存はパック単位なので「中を分ける」だけでは混ざりを検査できない。
  ドメイン（`Shop::Store`・`Notices::Board`）と利用者の画面は元のパックに残し、行員の画面はその公開 API だけを使う。
  そのためにお知らせの `Notice` を公開した（読み取りだけ。書き込みは `Board`）
- 利用者画面（packs/customer）のコントローラの名前空間は `Customer::` から `Netbank::`（ネットバンキング）に変えた。モデル `Customer` とぶつかるため。
  URL とルート名（`account_path` など）は変わらない
- packs/ui はだれがログインしているかを知らない（以前は `Current.user` を見ていた）。名前とログアウトは
  `staff_header` / `customer_header` が `content_for :account` に入れる
- テストのヘルパー: `create_staff` / `create_customer(name:)`、`sign_in_as_staff` / `sign_in_as_customer`（本物のログイン画面に POST する）

### packwerk の気づき（商店を作って）

- 商店は銀行の公開 API（`Bank` / `Events` / 例外 / 読み取りモデル）だけで作れた。プロセスマネージャは
  銀行のイベント（`TransferCompleted` / `TransferFailed`）を購読するので、銀行側の変更はいらない
- 商店のテストで銀行の非公開ジョブ（`Transfers::SettleJob`）だけを流そうとして privacy 違反になった。
  `perform_enqueued_jobs(except: Shop::PaymentJob)` のように「自分のジョブ以外」と書けば済む
- 画面の土台（`ApplicationController`・レイアウト・`churu` などのヘルパー・`account_path`）はルートにあり、
  パックからは依存できない。商店は `ActionController::Base` から直接作り、レイアウトとヘルパーは名前で借りていた。
  定数ではないので packwerk には見えない依存
  → TODO の N で、レイアウトとヘルパーを UI 用の土台パック `packs/ui` に移した。packs/platform に置かなかったのは、
  当時はレイアウトがログイン中の利用者（identity の `Current`）を使っていたから（platform は「どこにも依存しない」）。
  Q0 でログインが行員と利用者に分かれてからは、レイアウトはだれがログインしているかを知らない（`content_for :account` で入れてもらう）
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

### 予約振込・高額振込の保留・取消と差し止め（TODO の Q3）

いままでの振込は1秒ほどで入金まで終わって止める隙がなかったので、「実行前」の状態を2つ足した。

```
予約振込  Bank#transfer(…, execute_on: 明日以降)
  Transfer$<id> … TransferScheduled（予約中。まだ引き落とさない）
        │ 実行日: Transfers::ExecuteDueJob（recurring、1時間ごと）→ Bank#execute_due_transfers
        ▼
  Account$<振込元> TransferDebited → Transfer$<id> TransferStarted（処理中）→ あとはふつうの振込
  引き落とせない（残高不足・凍結）… Transfer$<id> ScheduledTransferFailed（実行できず。お金は動かない）

高額振込  金額 ≥ しきい値（既定 300、CHURU_TRANSFER_HOLD_THRESHOLD）
  TransferDebited → TransferRequested → TransferHeld（保留中。SettleJob は何もしない）
  行員が通す   … TransferReleased（処理中）→ SettleJob が入金 → TransferCompleted
  行員が差し止め … TransferRefunded（払い戻し）→ TransferStopped

実行前（予約中・保留中）
  利用者の取消 … （引き落とし済みなら TransferRefunded）→ TransferCancelled（取消済み）
  行員の差し止め … （同上）→ TransferStopped（差し止め。理由は必須）
```

| 決めたこと | 中身 |
|---|---|
| 予約の引き落とし | **実行日に引き落とす**（受付時は引き落とさない）。本物の銀行の予約振込と同じで、それまでのお金は口座にある（利息もつく）。受付時に残高が足りなくても受け付け、確認画面で「実行日までに入金がないと振り込まれません」と警告する。実行日に足りなければ「実行できず」で終わる（再挑戦しない。お金は動いていないので組戻しもない） |
| 実行日 | 明日〜365 日先。今日・過去はエラー（今日ならふつうの振込）。実行日の 0 時ちょうどではなく、その日のうちに1時間ごとのジョブが拾う（止まっていた時間があっても次の回で実行する） |
| 保留の引き落とし | **受付時に引き落とす**（ふつうの振込と同じ）。お金を押さえておかないと、通したときに残高がないことがあるため。だから保留の取消・差し止めは払い戻しになる |
| 高額の予約振込 | 実行日に引き落としたあと保留になる（しきい値は実行したときの設定）。予約中のうちに差し止めることもできる |
| 取り消せるのは | 予約中・保留中だけ。処理中（SettleJob の入金待ち）・完了・組戻しなどは不可（完了したものは行員の組戻し） |
| 競合 | 取消と実行（予約のジョブ・行員の通す）がぶつかったら、`Transfer$<id>` の expected_version で後から書いた方が `ConcurrentModification` になり、トランザクションごと戻る（取消の払い戻しも、実行の引き落としも残らない）。まとめて実行するジョブは負けた1件を飛ばして続ける |
| 商店の支払い・返金 | **保留の対象外**（`holdable: false`）。相手が決まった加盟店への支払いで、振り込め詐欺対策の保留の目的に合わない。保留すると在庫の引き当てが遅れ、返金まで保留されると利用者を待たせる。商店は予約振込も使わないので、商店のプロセスマネージャ（TransferCompleted / Failed の購読）はそのまま |
| だれが | 取消は自分の口座からの振込だけ（`cancel_transfer(id, from: 口座番号)`。他人のものは NotFound → 404）。通す・差し止めは行員の画面だけ。actor は取消・差し止めのイベントの metadata（`transfers.cancelled_by`） |

画面:

| だれ | 場所 | できること |
|---|---|---|
| 利用者 | 口座ページの振込フォーム | 「実行日」（空ならすぐ）。確認画面に実行日・保留の警告 |
| 利用者 | 口座ページの「予約・保留中の振込」 | 「取り消す」→ Frame `cancellation` で確認 → 確定（`/accounts/:number/transfers/:id/cancellation/new`） |
| 行員 | 振込一覧 `/admin/transfers` | 保留中に「通す」「差し止める」、予約中に「差し止める」→ Frame `hold` で確認 → 確定。保留が何件あるかを一覧の上に出す |

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
| 入金 | `Bank#reverse(number, event_id, reason:, approval:)` | `DepositReversed` | 残高が足りること（使ってしまった入金は取り消せない） |
| 出金 | 同上 | `WithdrawalReversed` | |
| 完了した振込 | `Bank#reverse_transfer(transfer_id, reason:, approval:)` | 振込先 `TransferCreditReversed` → 振込元 `TransferRefunded` → `Transfer$` `TransferReversed` | 振込先の残高が足りること。処理中・失敗（組戻し済み）は不可 |

- **取消・組戻しは二人承認**（TODO の Q2）: 行員が申請し、別の行員が承認したときに実行する（`Approvals::Desk`。「行員の権限: 窓口取引と二人承認」の節）。
  銀行は `approval:`（`Banking::Bank::Approval`）がないと、または申請者が実行者と同じだと `InvalidState`。ドライランは承認なしでよい
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
| 出金の依頼（利用者） | `bank.request_withdrawal(number, amount, memo:, dry_run:)` | Outcome の `request_id` が依頼ID。`balance_after` は処理されたときの残高（お金はまだ動かない） |
| 出金依頼の取消（利用者） | `bank.cancel_withdrawal(request_id, from: 自分の口座番号, dry_run:)` | `WithdrawalRequest#open?`（受付中）に「取り消す」。他人の口座の依頼は NotFound |
| 出金依頼の処理・お断り（行員） | `bank.process_withdrawal(request_id, dry_run:)` / `bank.reject_withdrawal(request_id, reason:, dry_run:)` | 窓口の一覧は `WithdrawalRequest.open`。依頼なしの出金（`withdraw`）はない |
| 入出金の取消 | `bank.reverse(number, entry.event_id, reason:, approval:, dry_run:)` | `LedgerEntry#reversible?` の行に「取消」。取消済みは `reversed?`、取消の行は `reversal?`。画面からは `Approvals::Desk#request_reversal` で申請する |
| 振込の組戻し | `bank.reverse_transfer(transfer.transfer_id, reason:, approval:, dry_run:)` | `Transfer#reversible?`（完了）の振込に「組戻し」。Outcome は振込元の口座。画面からは `Desk#request_transfer_reversal` |
| 凍結の解除 | `bank.unfreeze_account(number, approval:, dry_run:)` | 画面からは `Desk#request_unfreeze(number, reason:)`。凍結（`freeze_account`）は承認なし |
| 二人承認（packs/approvals） | `Approvals::Desk.new(actor:)` の `request_*`（→ `Submitted(approval_id, outcome)`）/ `approve(id, dry_run:)`（→ 銀行の Outcome）/ `reject(id, reason:)` / `withdraw(id)` | 一覧は `ApprovalRequest.pending`。ボタンは `#decidable_by?(actor)`（本人でない）・`#withdrawable_by?(actor)`（本人） |
| 利息を手で払う | `bank.pay_interest(date:, dry_run:)` → `[Outcome]` / 1口座なら `bank.pay_interest_to(number, date:, dry_run:)` → `Outcome` か `nil` | 行員の画面向け。ふだんはジョブに任せる |
| 利率の表示 | `Banking::Bank.annual_interest_rate`（文字列。例 `"0.365"`） | |
| 予約振込 | `bank.transfer(from, to, amount, memo:, execute_on: Date, dry_run:)` | 実行日は明日以降（`Banking::Bank::MAX_SCHEDULE_DAYS` 日先まで）。Outcome の残高は変わらない |
| 振込の取消（利用者） | `bank.cancel_transfer(transfer.transfer_id, from: 自分の口座番号, dry_run:)` | `Transfer#pending?`（予約中・保留中）の振込に「取り消す」。Outcome は振込元（保留中なら払い戻しで残高が増える） |
| 振込の差し止め（行員） | `bank.stop_transfer(transfer.transfer_id, reason:, dry_run:)` | `Transfer#pending?` に「差し止める」。理由は必須 |
| 保留を通す（行員） | `bank.release_transfer(transfer.transfer_id, dry_run:)` | `Transfer#releasable?`（保留中）に「通す」。Outcome は振込先（`balance_after` は入金後の額） |
| 保留のしきい値 | `Banking::Bank.hold_threshold`（整数） | 商店などの支払いは `transfer(…, holdable: false)` で対象外 |
| 予約の実行 | `bank.execute_due_transfers(date:)` / 1件なら `bank.execute_transfer(id, date:)` | ふだんはジョブに任せる。何度呼んでも1回分 |

通帳の種類（`LedgerEntry::KIND_LABELS`）に `interest`（利息）・`deposit_reversal` / `withdrawal_reversal`（取消）・
`transfer_reversal`（組戻しの引き戻し）が増えた。振込の状態（`Transfer::STATUS_LABELS`）に `reversed` が増え、
Q3 で `scheduled`（予約中）・`held`（保留中）・`unexecuted`（実行できず）・`cancelled`（取消済み）・`stopped`（差し止め）が増えた。
`transfers` には `execute_on`・`held_at`・`released_at`・`cancelled_at`・`cancel_reason`・`cancelled_by` の列。
状態の補足は `Transfer#status_note`（取消・差し止めの理由か、組戻し・実行できずの理由）。
予約中の振込は引き落としていないので通帳に出ない。保留中は「振込（送金）」の行に「保留中」、取消・差し止めると
その行が「取消済み」「差し止め」になり、払い戻しは「組戻し」の行（メモに理由）で出る。

### 管理画面での取消・組戻し・利息（packs/admin）

どれも入出金・振込と同じく Turbo Frame の中で「入力 → 確認（ドライラン）→ 確定（`_top` へ）」。
取消・組戻しは Q2 から**確定が「申請」**になり、別の行員が承認待ち（`/admin/approvals`）で承認すると実行される。

| 画面 | 場所 | 確認画面で見せるもの |
|---|---|---|
| 入出金の取消の申請 | 口座ページの通帳の「取消」→ Frame `reversal`（`/admin/accounts/:number/reversals/new?event_id=`） | 理由・承認されたときの残高の変化・発生するイベント |
| 振込の組戻しの申請 | 振込一覧と口座ページの通帳の「組戻し」→ Frame `reversal`（`/admin/transfers/:id/reversals/new`） | 振込元・振込先それぞれの承認されたときの残高の変化・イベント。口座ページから来たら申請後はその口座へ戻る（`back_to`）。申請中の振込は「組戻しの承認待ち」 |
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
- 支払い・返金の振込は、銀行の高額振込の保留の対象外（`Bank#transfer(…, holdable: false)`。理由は「予約振込・高額振込の保留」の節）

### 認証と権限（TODO の N、Q0 で行員と利用者を分けた）

- `/shop`（買い物）は利用者のログインが必須（`Shop::ApplicationController` で `CustomerAuthentication` を include）
- **購入者はログイン中の利用者にひも付いた口座（`account_ownerships`）だけ**。口座が複数あれば「支払う口座」で選べる
  （選んだ口座はセッションに持つが、使うたびに自分の口座の中から探し直す。他人の口座番号を送っても無視）。
  ひも付いた口座がなければ注文できない
- 注文履歴は自分の口座の分だけ。他人の注文ページは 404（あるかどうかも見せない）
- **行員が商店で買う場合**: 行員のアカウントでは買えない（行員のログインでは `/shop` に入れない）。買うなら利用者のアカウントを別に持ち、
  そこにひも付いた口座で買う。行員だからといって利用者の口座で代わりに買うことはできない（代理購入は銀行の業務ではないし、
  他人の口座から引き落とす入口を増やさない）
- **商品の登録・値段・入荷・商店の口座を開く・注文を全員分見る**のは行員だけ。`/shop/admin`（packs/shop_admin、`ShopAdmin::`）で、
  行員のログインがなければ行員のログイン画面へ。注文は `/shop/admin/orders/:id`（商品と在庫の管理の「最近の注文」から辿る。RES Browser へのリンクも）
- だれの操作かは、商店のイベントの metadata の actor に `customer:<id>`（買い物）/ `staff:<id>`（管理）で残る（Q0 より前は `shop:<メール>`）
- 見た目: 買い物はねこテーマ（`layouts/shop/customer` → `layouts/cat`）、管理は管理画面と同じ見た目
  （`layouts/shop_admin` → `layouts/application`）。どちらも packs/ui のレイアウト

**商品の管理を `/admin`（packs/admin）に寄せず、`/shop/admin`（packs/shop_admin）にした理由**:
管理画面に寄せると admin → shop の依存ができ、admin はドメインが増えるたびに全部に依存する「何でも屋」になる。
はじめは shop の中（`Shop::Admin::`）に置いていたが、Q0 で行員と利用者のログインを別のパックにしたとき、shop が両方のログインに
依存することになったので、管理の画面だけを packs/shop_admin に出した。shop_admin は shop の公開 API（`Shop::Store`・読み取りモデル）だけを使う。
注文の状態のバッジ（`shop/orders/_status`）だけは shop の部品を名前で借りている。
管理画面のメニューの「商店の管理」はリンク（ルート名）だけで、定数の依存はない

## 銀行からのお知らせ（packs/notices）

行員が出したお知らせを、利用者画面のページの頭の吹き出しと、ねこのセリフ窓で知らせる。キャンペーン（条件を満たすと特典が自動入金）はまだで、あとで足せる形にだけしてある。

| だれ | 場所 | できること |
|---|---|---|
| 行員 | `/admin/notices`（管理画面のメニュー「お知らせ」） | 出す・直す・掲載終了。種類（お知らせ / お願い / メンテナンス）、タイトル・本文、掲載期間（終了は空なら終わりなし）、対象（全員 / 選んだ利用者）、重要 |
| 利用者 | 利用者画面のどのページにも | ページの頭にお知らせの吹き出し（最大3件、ほかは「ほかに N 件のお知らせ」）、メニューの「お知らせ」（ベル）に未読のバッジ |
| 利用者 | `/notices`・`/notices/:id` | 一覧（未読は NEW）と本文。開くと既読 |

- **見えるもの**: いま掲載中（`starts_at <= 今 < ends_at`）で、自分が対象のものだけ。期間外・対象外は一覧に出ず、開いても閉じても 404
- **既読と「閉じる」**: 利用者ごとに `notice_receipts`（`read_at` / `dismissed_at`）。ふつうのお知らせは未読のあいだ吹き出しに出て、開くか × で消える。
  **重要なものは開いて既読になっても、× で閉じるまで吹き出しに出し続ける**（本文のページにも「読みました（吹き出しを閉じる）」）
- **掲載終了**は消さずに `ends_at` を今にする（だれが読んだかは残る）。始まる前のものを終えたら、始まりも今にする
- **ライブ更新**: `Notices::Board` が保存したら `Notices::RefreshJob` が Turbo の refresh（morph）を `"notices"`（全員）に送る。
  掲載の始まり・終わりが先なら、その時刻にも送る（`set(wait_until:)`。Solid Queue）。既読・閉じたは `[customer, :notices]` に送ってほかのタブにも映す。
  refresh は「取り直して」という合図だけで中身を運ばないので、対象外の人に届いても何も漏れない
- **動き**: morph で新しく入った吹き出しだけが「ぽん」と出る（Stimulus の `notices--inbox` が `.is-fresh` を付ける）。
  ねこのセリフ窓にも知らせる（`cat:say`。重要なものはびっくり顔）。ページを開いたときやバッジは動かさない。`prefers-reduced-motion` なら止める
- **Turbo の prefetch に注意**: Turbo 8 はリンクにホバーすると先読みする。「開いたら既読」の GET が先読みされて、マウスを乗せただけで既読になった。
  吹き出しと一覧に `data-turbo-prefetch="false"` を付け、サーバーでも `X-Sec-Purpose: prefetch` のときは既読にしない（応答は `no-store`）

### パッケージの境目

- customer からは `helper Notices::InboxHelper` して、レイアウトで `<%= notices_inbox %>` を1回呼ぶだけ。中で `content_for` の
  `:head`（CSS）・`:nav`（バッジ）・`:page_top`（吹き出し。packs/ui の `layouts/application` が main の頭に出す）を入れる。
  ヘルパーの定数が「notices を使っている」しるしになって、packwerk で customer → notices の依存が見える
- 行員の画面は packs/notices_admin（`NoticesAdmin::`、`/admin/notices`）。はじめは packs/notices の中（`Notices::Admin::`）だったが、
  Q0 で notices が行員と利用者の両方のログインに依存することになったので出した（商店の管理と同じ）。notices_admin は
  `Notices::Board`（書き込み）と `Notice`（読み取り）だけを使う。admin が notices に依存しないよう、管理画面のメニューはリンク（ルート名）1つだけ
- ライブ更新の購読は利用者用のチャンネル（`customer_stream_from "notices"` と `customer_stream_from current_customer, :notices`）
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

## 窓口の整理券と窓口チャット（packs/counter・packs/counter_admin、TODO の S）

いままで画面の自動更新は Turbo に任せていた（「取り直して」の合図 refresh を送るだけ）。ここでは **Action Cable のチャンネルを自分で書いた**。
サーバーとブラウザが同じ線（WebSocket）の上で、小さな JSON を**両方向**にやりとりする。

| だれ | 場所 | できること |
|---|---|---|
| 利用者 | `/counter`（メニューの「窓口」） | 番号札を取る →「あなたは 5 番。前に 2 人」がその場で進む。窓口に行員がいるか。札を返す。呼ばれたら、ねこが「5 番の方、窓口へどうぞにゃ！」（うれしい顔で弾む）、同じページがチャットになる |
| 行員 | `/admin/counter/queue`（メニューの「整理券とチャット」。窓口（出金依頼）の隣） | お待ち・対応中・最近の終わりの列。「次の方」で呼ぶとチャットへ。チャットの横にその利用者の受付中の出金依頼。「出金依頼の画面を案内する」「終わる（次の方へ）」 |

### Action Cable の流れ（だれが何を購読し、何がどこへ流れるか）

```
                    ┌───────── WebSocket 1本（/cable）。Cookie でだれの接続かが決まる ─────────┐
                    │  ApplicationCable::Connection … current_customer（利用者）/ current_staff（行員）│
                    └──────────────────────────────────────────────────────────────┘

 利用者（ミケ）のブラウザ                       サーバー（packs/counter）                       行員（たま）のブラウザ
 ─────────────────────                 ─────────────────────                 ─────────────────────
 counter--ticket                        Counter::TicketChannel
   購読 {ticket_id: ミケの札}  ─────────▶  持ち主か確かめて stream_for 札
                               ◀─────────  position {ahead: 1, staff_at_counter}           counter--queue
                               ◀─────────  called {number: 5, staff_name: "たま"}           購読 {} ─────▶ Counter::QueueChannel
                               ◀─────────  closed                                               行員か確かめて stream_from "counter:queue"
                                                                                                 subscribed で在席（窓口に行員がいる）
                                                                        changed ─────────▶ 列の Frame を読み直す
 counter--chat（呼ばれたら）             Counter::ChatChannel（札ごとの部屋）              counter--chat
   購読 {ticket_id, role: "customer"} ─▶  role と接続の持ち主を確かめて stream_for 札  ◀─ 購読 {ticket_id, role: "staff"}
   perform("speak", {body})  ─────────▶  Desk.speak → 保存 → broadcast_to 札        ◀─ perform("speak", {body})
   perform("typing")         ─────────▶  broadcast_to 札（保存しない）              ◀─ perform("typing")
                               ◀─────────  message / typing / presence / closed ─────────▶
   subscribed / unsubscribed  ─────────▶  在席（CounterPresence）の出入り → presence ─────▶「ミケ さん: チャットを開いています」

 ふつうの HTTP（フォーム）: 札を取る POST /counter・返す DELETE /counter・次の方 POST …/queue/call・終わる POST …/tickets/:id/finish
   → Counter::Desk が書いて、Counter::Broadcasts が上の矢印（◀──）を流す
```

| チャンネル | 購読できる人（接続の持ち主で確かめる） | サーバー → ブラウザ | ブラウザ → サーバー |
|---|---|---|---|
| `Counter::TicketChannel`（`stream_for 札`） | 利用者としてつないだ、**その札の持ち主だけ**。他人の札の id・行員の接続・返した札は断る | `position`（前に何人・窓口に行員がいるか。購読した瞬間にも `transmit`）/ `called` / `closed` | なし |
| `Counter::ChatChannel`（`stream_for 札`） | `role: "customer"` … 利用者としてつないだ、札の持ち主。`role: "staff"` … 行員としてつないだ人（だれでも見られる）。どちらも札が「対応中」のときだけ。名乗った role と接続が合わなければ断る | `message` / `typing` / `presence` / `closed` / `error`（自分にだけ） | `speak`（発言。行員は `kind: "withdrawal_guide"` も）/ `typing` |
| `Counter::QueueChannel`（`stream_from "counter:queue"`） | 行員としてつないだ人だけ | `changed`（列が変わった） | なし |

- **だれかを確かめる場所**: 購読（`subscribed`）のときに接続の `current_customer` / `current_staff` で確かめ、だめなら `reject`。
  発言（`speak`）のときも `Counter::Desk` がもう一度確かめる（発言できるのは札の利用者と**呼んだ行員だけ**。ほかの行員は見るだけで、送ると `error` が自分にだけ返る）
- **同じブラウザで行員と利用者の両方にログイン**していると、接続は両方を持つ。チャットは `role` で「どちらとして入るか」を決め、その role の人が接続にいるかを確かめる
- **中身は JSON だけ**（HTML を送らない）。発言はブラウザで `textContent` として入れる（HTML が書かれても文字のまま）。行員の列だけは
  「変わった」の合図を受けて Turbo Frame を読み直す（列の見た目をサーバーの ERB 1か所で持つため）
- **在席**: 購読ごとに `counter_presences` に1行（`subscribed` で足し `unsubscribed` で消す）。タブを2つ開けば2行なので、1つ閉じてもまだ在席。
  サーバーが落ちると `unsubscribed` が呼ばれず残るので、サーバーの起動時に全部消す（`packs/counter/config/initializers/counter.rb`）
- **入力中**: 1.5 秒に1回まで `typing` を送り、相手の画面は最後に届いてから 3 秒「入力中…」を出す。保存しない。日本語の変換中の Enter では送らない
- **ブラウザ側**: Stimulus（`packs/counter/app/javascript/controllers/counter`）で `@rails/actioncable`（importmap で gem の `actioncable.esm.js` を pin）の
  `createConsumer()` を1つ作り（`consumer.js`）、`consumer.subscriptions.create({ channel, … }, { received })` で購読。Stimulus の `disconnect` で `unsubscribe`
- Turbo のライブ更新（`StaffStreamsChannel` / `CustomerStreamsChannel`）とは別の接続（Turbo は自分の consumer を持つ）。どちらも同じ `ApplicationCable::Connection` を通る

### 試し方（1つのブラウザで3人）

Cookie はホストごとに別なので、`localhost` と `127.0.0.1` で別の利用者になれる（開発では Action Cable も `127.0.0.1` からつなげるようにしてある。`config/environments/development.rb`）。
行員と利用者は Cookie の名前が別なので、同じホストでも両方にログインできる。

1. タブ1 `http://localhost:3002/session/new` でジンジベル → `/counter` で番号札を取る（1 番）
2. タブ2 `http://127.0.0.1:3002/session/new` でミケ → `/counter` で番号札を取る（2 番・前に 1 人）
3. タブ3 `http://localhost:3002/admin/session/new` でたま → `/admin/counter/queue`（タブ1・2 に「窓口に行員がいます」）→「次の方」
   → タブ1 でねこが「1 番の方、窓口へどうぞにゃ！」、タブ2 は「次があなたの番です」
4. タブ1 とタブ3 でチャット（入力中・在席が出る）。タブ3 の「出金依頼の画面を案内する」→ タブ1 にボタン →「終わる（次の方へ）」→ もう一度「次の方」でミケ

Turbo の画面の入れ替えは、ブラウザのタブが見えていないと止まることがある（組み込みのブラウザのペインが隠れているときなど）。

### Q1 の窓口取引とのつながり

- 行員のチャットの横に、その利用者の**受付中の出金依頼**（`WithdrawalRequest.open`、口座は顧客台帳から）と「窓口（出金依頼）で処理する」。依頼が出たら Turbo の refresh で増える（チャットの欄は `data-turbo-permanent` で morph から外す）
- 行員が「出金依頼の画面を案内する」を押すと、決まった文の発言（`kind: "withdrawal_guide"`）が届き、利用者の画面ではその発言に**自分の口座の「出金の依頼」へのボタン**が付く（新しいタブで開くのでチャットは切れない）
- 出金そのものは今までどおり「利用者が依頼 → 行員が窓口で処理」。チャットからお金は動かさない

### 決めたこと

| 決めたこと | 中身 |
|---|---|
| 記録 | **ふつうの表**（`counter_tickets`・`counter_messages`）。イベントソーシングにしない。お金も、ほかの集約とまたがる決まりもなく、番号札は「待っている → 呼ばれた → 終わり／返した」という単純な状態。チャットは文の積み重ねで、書き直さない。消さずに状態と時刻（取った・呼んだ・終わった、だれが）を残せば記録として足りる。RES にすると読み取りモデルとプロジェクションまで要るのに、得るものがない（お知らせと同じ考え方） |
| 番号 | 日ごとに 1 から（`service_date` と `number` の一意インデックス）。同時に取ってぶつかったら取り直す |
| 1人1枚 | 「お待ち」「対応中」の札は1人1枚（部分インデックス）。もう持っていれば同じ札を返す |
| 次の方 | いちばん前の札を `UPDATE … WHERE status = 'waiting'` で取る。2人の行員が同時に押しても、1枚を呼ぶのは1人だけ（負けたほうは次の札へ）。話している途中の行員は呼べない（先に「終わる」） |
| 終わる | 呼んだ行員でなくても終われる（席を外したままの人の代わりに閉じられるように）。発言は呼んだ行員だけ |
| 札を返す | 待っているあいだも、呼ばれたあとも返せる（呼ばれたあとなら行員のチャットに closed が届く） |
| パック | 整理券とチャットのドメイン・チャンネル・利用者の画面は `packs/counter`（利用者のログインに依存）。行員の画面は `packs/counter_admin`（行員のログイン・銀行・顧客台帳に依存）。お知らせ・商店と同じ分け方。チャンネルは接続の `current_staff` を見るだけで `Staff` の定数は使わないので、counter は staff_identity に依存しない |
| メニュー | 管理画面の `layouts/admin` と利用者画面の `layouts/customer` に1行ずつ（ルート名だけ。定数の依存はない） |

## 利用者画面の見た目（日本アニメ的 kawaii、TODO の M）

最初の「ねこ・ちゅ〜る」のテーマは「かわいいというより幼い」ので、方向を**日本アニメ的 kawaii**に変えた
（見本はデザインキャンバスの Main / Happy / Faces / Cat）。行員の画面の見た目は変えていない。

- **色**: 桜ピンク `#FFB7C9`・空色 `#9ED8F5`・クリーム `#FFF8EC`（地）・紺 `#2B2D52`（主線と文字）。ちゅ〜るのオレンジは使わない（残高も紺）。
  金額は入金 `#1F6FA8`・出金 `#C2365E`、補足の文字 `#5B5E85`（どれも白とクリームの上で 4.5:1 以上）
- **ダーク**: 紺の地 `#1B1C38`・カードの面 `#26284A` に、主線と文字はクリーム `#FFF8EC`。補足 `#C3C5E6`、入金 `#8ED0F7`、出金 `#FF9FB8`。
  ピンクのボタンの文字は紺の地の色、ぼかさない影は地より暗い `#0D0E20`。ねこはキャラクターの色なので変えない（どれも 4.5:1 以上）
- **セル画っぽさ**: カード・ボタン・入力欄に 2〜2.5px の主線と、ぼかさない影（`0 4px 0` / `0 5px 0`）。角丸 16〜20px。
  グラデーションと水玉はやめ、アクセントにスクリーントーンの網点（`.tone`、カードの右上だけ）。見出しはマーカー線（`.marker`）
- **文字**: Zen Maru Gothic（500 / 700 / 900）、数字は等幅。残高は数字を大きく、単位「ちゅ〜る」を小さく
- **アイコン**: 絵文字はやめて線画（`Ui::ThemeHelper#icon`、インラインの stroke SVG）。商品の絵文字・お知らせの種類の絵文字は行員の画面だけで使う
- **ねこ**（`cat(face:)`、`ui/_cat`）: 主線つき、大きなキラキラの目。表情は 4 つ（ふつう・うれしい・びっくり・しょんぼり）を 1 つの SVG に描いておき、
  `data-face` で出し分ける。出来事で切り替える:

  | 表情 | いつ |
  |---|---|
  | うれしい（弾む・キラッ） | 入金が届いた（morph で通帳に入った行）、振込が完了した、お買いもの完了 |
  | びっくり | 確認の画面（振込・取消・注文。まだ確定していない）、重要なお知らせ |
  | しょんぼり | 残高不足などで振込・注文ができなかった、組戻しで引き戻された・入金が取り消された、口座が凍結中・解約済み |
  | ふつう | それ以外（あいさつ・ふだんのセリフ） |

- **セリフ窓**（`ui/_serif`、Stimulus の `serif`）: ノベルゲーム風に画面の下に固定（名札「ちゅーる」と ▼）。文字を 1 文字ずつ出す（クリックで全部出る）。
  **猫語はここだけ**で、ほかの文（見出し・ボタン・メッセージ）は普通の日本語。
  ページのセリフはテンプレートで `cat_says "…", face: :sad`、Turbo Frame の中（確認画面など）からは `cat_say_tag`（Stimulus の `cat-say`。
  消えるとページのセリフに戻る）、JS からは `window` に `cat:say`（`{ text, face, bounce }`）。読み上げには全文を 1 回だけ（`role="status"`）
- **振込完了の演出**: すぐの振込を確定すると `flash[:celebrate]` に振込 ID を入れ、口座ページの通帳の行（`transfer_status`）が「完了」になった瞬間に
  `dialog.hooray`（集中線・「振込完了！」・うれしいねこ・はんこ・セリフ窓）を開く。描いた時点でもう完了していても出す。
  ジョブの refresh の配信は自分のリクエストのものとして無視されることがあるので、直後だけ自分で数回描き直して完了を拾う
- **動きは出来事のときだけ**: うれしいときの弾む動き（つぶれて伸びる）とキラッ、表情が変わるときの小さな動き、振込完了の集中線、
  届いた通帳の行・残高の変化。常時ふわふわ・まばたき・ホバーで傾く・ページを開くたびのカウントアップはやめた。`prefers-reduced-motion` で全部止まる
- **出金依頼などのフォームを足すとき**: `.card` `.form` `.button`（`.primary` / `.small`）・`.confirm`・`.badge`・`.flash`・`.hint` をそのまま使えば
  この見た目になる。見出しは `<h2><%= icon(:send, size: 22) %><span class="marker">…</span></h2>`、確認画面には `cat_say_tag "…", face: :surprised`

## Hotwire で使っているもの

| 機能 | 場所 |
|---|---|
| Turbo Frame（遅延読み込み・Frame 内の画面遷移） | 口座ページの入出金・振込フォーム（入力 → 確認 → 確定）。利用者画面は振込だけ |
| Turbo Frame + `data-turbo-action="advance"` | 時点指定の残高（URL の `?date=` も進む） |
| Turbo 8 の refresh（morph） | `turbo_refreshes_with` + `turbo_stream_from`。ほかのプロセスからの入出金も即反映 |
| Stimulus | `amount_controller`（+10 / +50 ボタン）、`autosubmit_controller`（日付を変えたら送信） |
| 利用者画面の動き（Stimulus + CSS、外部ライブラリなし） | `serif_controller`（ねこのセリフ窓。1文字ずつ・表情の切り替え）、`cat_say_controller`（Frame の中からセリフを変える）、`count_up_controller`（morph で残高が変わると前の値から数える）、`arrival_controller`（morph で届いた通帳の行を出し、種類に合わせてねこのセリフ）、`transfer_status_controller` → `celebrate_controller`（振込完了の演出 `dialog.hooray`）。`prefers-reduced-motion` なら止める |
| View Transitions | 利用者画面だけ `<meta name="view-transition">`。一覧と口座ページで残高がつながる |
| Turbo の refresh（morph）+ Solid Queue の予約 | 銀行からのお知らせ。出した・直した・掲載の始まり / 終わりの時刻に `Notices::RefreshJob`。新しい吹き出しだけ CSS で出る。`data-turbo-prefetch="false"`（開くと既読のため） |
| Action Cable（自作のチャンネル）+ Stimulus + `@rails/actioncable` | 窓口の整理券とチャット。`counter--ticket`（自分の札）・`counter--chat`（双方向。発言・入力中・在席）・`counter--queue`（行員の列。届いたら Frame を読み直す） |

## MCP（packs/mcp）

Claude などの MCP クライアントから銀行を使うための入口。公式の Ruby SDK（`mcp` gem）で、
Rails の同じプロセスの中に Streamable HTTP のエンドポイント `/mcp` を置いている
（stateless・JSON で返す）。同じプロセスなので、振込の入金ジョブや画面のライブ更新もそのまま効く。

| ツール | 中身 |
|---|---|
| `list_accounts` | 口座一覧（口座番号・名義・状態・残高） |
| `get_account` | 残高と通帳（新しいほうから `limit` 件） |
| `balance_at` | ある日の終わり時点の残高。起算日基準（`as_of`）と記帳日基準（`as_at`）の両方 |
| `list_transfers` / `get_transfer` | 振込の一覧・状態（予約中 / 保留中 / 処理中 / 完了 / 組戻し / 実行できず / 取消済み / 差し止め）。予約は `execute_on` |
| `deposit` / `request_withdrawal` / `transfer` | 入金・出金の依頼・振込。**既定はドライラン**。`confirm: true` のときだけ書き込む。`transfer` は `execute_on`（YYYY-MM-DD）で予約振込。出金は依頼を出すだけで、行員が窓口で処理すると出金される（Q1。`withdraw` はなくした） |

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

## イベントビューア（packs/event_viewer、TODO の R）

`/admin/events`（行員だけ。管理画面のメニューの「イベント」）。英語の RES Browser（`/res`）の代わりに、イベントストアの中身を
**日本語で・目で見て**たどる画面。読むだけで、何も書き込まない。英語の RES Browser は右上の「詳しく見る（英語）」に残してある。

```bash
bin/rails churu:demo_events   # 眺めるための出来事を一通り起こす（db:seed のあとで。流すたびに1組増える）
```

デモの出来事（`db/demo_events.rb`）: 窓口での入金・起算日を3日さかのぼった入金・振込・凍結中の口座への振込（組戻し）・凍結の解除（二人承認）・
高額振込の保留を通す・お買いもの（完了 / 在庫が足りず返金 / 残高が足りず支払いの失敗）・出金依頼（出金 / お断り）・入金の取消（二人承認）・利息。
ジョブはその場で動かす（inline）ので、流し終わったときには振込の入金や商店の引き当てまでそろっている。

### 使い方

| 画面 | 場所 | できること |
|---|---|---|
| 一覧と生中継 | `/admin/events` | 新しい順の一覧。出来事の名前（「振込の引き落とし」など）・種類の色とアイコン・入れ物（「口座 0000001（オルカ）」「振込 #c49f」）・金額や相手・だれが（「窓口のたま（行員）」）。**新しい出来事が上から1件ずつふわっと流れてくる**（「止める」でためておき、「再開する」で順に流す）。種類・口座・日付で絞り込める（絞り込み中は生中継しない） |
| 1件の中身 | `/admin/events/:id` | 中身（data）と付帯情報（metadata）を日本語の項目名で表に（金額は「120 ちゅ〜る」、口座は名義つき、だれは名前、ほかの出来事・振込・注文はリンク。元の英語の項目名は小さく右に）。入っているストリーム（もともとの入れ物 / リンク） |
| つながりの図 | 1件の中身の下 | その出来事と**ひとつながりの出来事**を、上から下へ時間の順に。同じ処理で書いた出来事を枠で囲み、きっかけ（causation_id）でつながるたびに1列右へずらす。「再生」で起きた順に1つずつ光る。出来事をクリックするとその出来事へ |
| タイムマシン | `/admin/events/time_machine` | 口座を選び、つまみ（何件目まで足すか）を動かすと、その出来事まで足し合わせた残高・状態・通帳。「コマ送り」で1件ずつ足していき、残高の数字がその場で変わる。上に足し算（0 ＋300 −50 … = 残高）。**起算日の順 / 記帳日の順**を切り替えられる |
| レーン図 | `/admin/events/lanes` | 振込・注文・出金依頼・二人承認を1つ選ぶと、かかわった入れ物（振込元の口座・振込・振込先の口座・注文・商店の口座・商品 …）を横に並べ、出来事を時間の順に矢印でつなぐ。「再生」もある |

### イベントソーシングの見どころ（何を見ると何が分かるか）

- **残高は「出来事を順に足し合わせた結果」**（タイムマシン）: 読み取りモデル（`accounts.balance`）を見ずに、口座の出来事を1件目から足すと、
  いまの残高とぴったり同じになる。つまみを戻せば、どの時点の残高にも戻れる。消したり書き換えたりしないから、過去がそのまま残っている
- **取消も「逆向きの出来事」**（一覧・タイムマシン）: 入金の取消は、元の入金を消さずに「入金の取消」（−100）を足す。通帳には両方が残る
- **起算日と記帳日**（タイムマシンの切り替え）: デモの「3日前の持ち込み分」は、記帳日の順だと記帳したところに、起算日の順だと3日前（口座の開設より前！）に来る。
  どちらの順で足しても、いまの残高は同じ。「本当はいつのことか」と「銀行がいつ知ったか」は別の時間
- **1回の操作がいくつもの入れ物に書かれる**（レーン図）: 振込1件で、振込元の口座（引き落とし）・振込（受付・完了）・振込先の口座（入金）の3つの入れ物に出来事が入る。
  口座の出来事は振込の入れ物にもリンクしてあるので、どちらからでもたどれる
- **ジョブが出来事を受けて続きをする（プロセスマネージャ）**（つながりの図）: 振込の受付の処理（利用者）→ きっかけの矢印 → 振込の処理（自動）が入金と完了。
  お買いものなら さらに → 商店の支払いの処理（自動）が引き当て・完了、在庫が足りなければ返金の振込 → 振込の処理 → 返金の完了…と、**右へ右へ階段になる**。
  これが correlation_id（ひとつながりの番号）と causation_id（きっかけの出来事）
- **人があとで操作した続き**（点線の「そのあと」）: 高額振込の保留を行員が「通す」、出金依頼を窓口で処理する、二人承認で別の行員が承認する、は
  きっかけ（causation_id）の記録がない（人がボタンを押したから）。同じ振込・依頼・申請の入れ物でつながっていることを点線で描く
- **同じトランザクション**（枠）: 「振込の引き落とし」と「振込の受付」、「入金の取消」「承認」「承認した操作の実行」は同じ処理の中で書かれ、全部書けるか全部書けないか
- **補償（あとから打ち消す）**: 凍結中の口座への振込は、いったん引き落としてから「払い戻し」と「失敗」。在庫切れの注文は、支払いのあとで「キャンセル」と「返金」。
  先に止めるのではなく、起きたことを打ち消す出来事を足して整える

### しくみ

| 部品 | 中身 |
|---|---|
| `EventLens::Catalog` | イベントの日本語の名前・種類（入金・出金・振込の手続き・止める・通す・依頼と承認・商店・口座。色とアイコン）・ひとこと説明、中身の項目名。**新しいイベントを足したらここにも1行**（`catalog_test` が全イベント分あるかを確かめる）。各パックの公開のイベント一覧（`Banking::Events` など）を定数で引く |
| `EventLens::Names` | ストリーム名・口座番号・actor を日本語に（`Account$0000001` → 口座 0000001（オルカ）、`staff:1` → 窓口のたま（行員）、`transfer-settlement` → 振込の処理（自動））。名義は公開の読み取りモデル（`Account`・`ShopProduct`）から。人の名前は見る画面が渡す（行員の画面は全員、利用者の画面は本人だけ。ほかは「銀行の行員」「ほかのお客さま」） |
| `EventLens::EventIndex` | イベントストアの全部を `event_store.read` で1回読み、correlation_id・業務の ID（振込ID・注文ID・出金依頼ID・申請ID）で引ける索引にする |
| `EventLens::Flow` | 1つの出来事から「ひとつながり」を集める: 同じ correlation_id、causation_id の先、同じ業務の ID をもつ出来事（口座と商品の入れ物は出来事が多すぎるのでたどらない）。それを「処理」（同じ actor・同じきっかけ・0.5 秒以内に続けて書かれたもの。ふつうは1トランザクションの目安。RES はトランザクションの区切りを残さない）に分け、きっかけ（:cause）・そのあと（:then）・同じ処理の中（:same）でつなぐ |
| `EventLens::Diagram` | つながりの図（Tree）とレーン図（Lanes）の座標と線。SVG は ERB で自分で描く（外部の図のライブラリは使わない） |
| `EventLens::TimeMachine` | 口座の入れ物を `read.stream(...).as_of` / `.as_at` で読み、`Banking::Events.balance_delta` で1件ずつ足す（`Banking::Statement` と同じ考え方を、1件ごとに） |
| `EventViewer::LiveJob` | 生中継。`subscribe_to_all_events` の非同期ハンドラ（コミット後に Solid Queue）で、一覧の1行を Turbo Stream（prepend）で配信。購読は `staff_stream_from`（行員の接続だけ） |
| `EventLens::EventsHelper` と `app/views/event_lens/*` | 表示の部品（一覧の1行・見出し・中身の表・つながりの図・レーン図・タイムマシン）。リンク先は画面ごとにちがうので、使う画面が `lens_event_path` / `lens_lanes_path` / `lens_time_machine_path` と `names` をヘルパーで用意する（リンクしないなら nil） |
| Stimulus（`controllers/event_lens/*`） | `live`（届いた行を `turbo:before-stream-render` で横取りし、ためておいて1件ずつ入れる・止める・再開）、`playback`（data-step の順に光らせる）、`time_machine`（つまみ・コマ送り・残高の数字）。`prefers-reduced-motion` なら動きを止める |

- 組み込みブラウザのペインが隠れていると requestAnimationFrame が止まり、Turbo Stream の描画が止まる（生中継が流れてこない）。アプリの不具合ではない（ペインを表に出すと動く）
- 同じホスト名だと Cookie はポートを区別しないので、別の作業ディレクトリのサーバー（3000 番と 3001 番）を `localhost` で同時に開くとセッションがぶつかって CSRF で弾かれる。片方を `127.0.0.1` で開く

### パッケージの境目と、公開されていなくて困ったこと

- **部品（packs/event_lens）と画面（packs/event_viewer・packs/customer）を分けた**: 利用者にも出来事の画面を作るとき、行員の画面のパックに部品があると、利用者の画面がそれに依存して行員のログイン（staff_identity）までつながってしまう。「画面のパックは片方のログインにだけ依存する」を守るため、ログインに依存しない部品のパックを作り、両方の画面がそれを使う。部品は「だれが見ているか」を知らず、人の名前とリンク先は画面が渡す
- event_lens の依存は banking・shop・approvals（公開のイベント一覧と読み取りモデル）と ui。event_viewer は加えて staff_identity（行員だけ）と customer_registry（利用者の名前）。だれも event_viewer に依存しない（管理画面のメニューはルート名のリンク1つ）
- **ストリーム名の作り方が非公開**: `Banking::Account.stream_name` などは銀行のパックの非公開のクラスにあるので、`"Account$#{番号}"` を文字列で書いている（`Catalog.home_stream`・`TimeMachine`・`Search`）。
  銀行が名前を変えたらずれる。直すなら、銀行の `app/public` に「ストリーム名の一覧」（例 `Banking::Streams.account(number)` / `.transfer(id)`）を公開する。商店（`Order$`・`Product$`）・二人承認（`Approval$`）も同じ
- **correlation_id で引けない**: RES の読み取り API に correlation_id での検索がないので、全部を読んで手元で引いている（学習用の小さなストアなら足りる）。
  大きくなったら、イベントストア本体（ルートの `config/initializers/event_store.rb`）で RES の `RubyEventStore::LinkByCorrelationId` / `LinkByCausationId` を購読して
  `$by_correlation_id_<id>` の入れ物にリンクし、それを読む。リンクは書き込みなので、このパックではなくイベントストアの持ち主（ルート）でやる。過去の分は1回流し直しが要る
- **actor の名前**: 管理画面の `Admin::ActorsHelper`（非公開）と同じことを `EventViewer::ApplicationController.names`（`EventLens::Names` に名前を渡す）でもしている（自動の処理の名前も足した）。
  ほかでも要るようになったら、actor の文字列 → 名前を staff_identity / customer_registry の公開の部品にする

### 利用者の「わたしの出来事」（/events）

利用者画面のメニューの「わたしの出来事」。行員の画面と同じ部品（日本語のイベント名・つながりの図・タイムマシン）を、ねこテーマの見た目で使う（`MyEvents::`、packs/customer）。
ねこのちゅーるがセリフ窓で、しくみをやさしく説明する（「通帳は、出来事を順番に足していったものなんだにゃ」など）。

| 画面 | 場所 | できること |
|---|---|---|
| 出来事のならび | `/events` | 自分の口座にかかわる出来事を新しい順に（100 件まで）。種類・口座で絞り込める。**生中継は自分の分だけ**（届くとねこが「新しい出来事が届いたにゃ」） |
| 1件の中身 | `/events/:id` | 中身と「いつ・だれが・どこから」の表、つながりの図（再生つき） |
| タイムマシン | `/events/time_machine` | 自分の口座を選んで、出来事を1件ずつ足していく（起算日の順 / 記帳日の順） |

**見せる範囲**（`MyEvents::EventScope`）:

- 見せる: 自分の口座のストリームの出来事、自分の口座が振込元か振込先の振込・自分の注文・自分の出金依頼の出来事、自分の注文のための在庫の引き当て
- 見せない: 他人の口座の出来事（振込先の口座への入金も、相手の口座の出来事なので出さない。つながりの図では、その先を「そのあと」の点線でつなぐ）、
  二人承認の申請・承認（行員の内部の手続き）、商店の開店・商品の登録・入荷、ほかの人の注文
- 付帯情報は「だれが・いつ・ひとつながりの番号・きっかけ」だけ。二人承認で実行された取消でも、申請者・承認者・申請 ID や、接続元・リクエストは出さない
- 人の名前は本人だけ。行員は「銀行の行員」、ほかの利用者は「ほかのお客さま」。口座の名義は出す（通帳の振込の相手と同じ）
- 他人の口座（`?account=`）・他人の出来事・行員だけの出来事の URL は 404（あるかどうかも見せない）。他人の出来事・口座へのリンクも作らない
- 生中継: `MyEvents::EventsLiveJob`（`subscribe_to_all_events`）が、かかわる口座の持ち主のうち EventScope が通す人にだけ、`[利用者, :events]` へ Turbo Stream を送る。
  購読は `customer_stream_from current_customer, :events`（利用者用の鍵で署名。ほかの人のストリームは購読できない）
- パック: 画面は packs/customer の中（利用者画面のレイアウト・ログインをそのまま使う）。名前空間を `Netbank::` にしないのは、メニューの「わたしの口座」の印（`netbank` の画面にいるか）と分けるため。
  依存に event_lens（部品）・shop（自分の注文を見分ける `ShopOrder`）・customer_registry（生中継の相手を引く `Customer.owning`）を足した。二人承認（approvals）には依存しない

## TODO

| # | やること | 先に必要 | 主な場所 |
|---|---|---|---|
| ~~A~~ | ~~packwerk 導入、銀行を `packs/banking` へ~~（済） | | |
| ~~B~~ | ~~認証（Rails 8 の `generate authentication`）、ユーザーと口座のひも付け~~（済。Q0 で行員と利用者に分けた） | | `packs/staff_identity`・`packs/customer_identity`・`packs/customer_registry` |
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
| ~~M~~ | ~~利用者画面はとにかくかわいく。アニメーション（残高のカウントアップ、入金でふわっと、振込完了のお祝い）。reduced-motion に配慮~~（済。アニメ kawaii に作り直し済み。「利用者画面の見た目」） | C | `packs/customer` |
| ~~N~~ | ~~商店を認証につなぐ: 購入者はログイン中の利用者の口座、商品・在庫の管理は行員だけ。画面の共通部品（ヘルパー・レイアウト）を UI 用のパックへ~~（済） | B, D | `packs/shop`・`packs/ui` |
| ~~O~~ | ~~管理画面に取消・組戻し・利息の手動実行のボタン~~（済。「管理画面での取消・組戻し・利息」） | F, G | `packs/admin` |
| P | 利用者画面に銀行からのお知らせ・お願い・キャンペーン（**お知らせ・お願いは済**。キャンペーン = 条件を満たすと特典が自動入金、は未） | C, N（キャンペーンは L） | `packs/notices`（キャンペーンは新しいパック） |
| Q | 行員の権限を本物の銀行に寄せる。~~**Q0** 行員と利用者の完全な分離: 別のモデル・テーブル・ログイン画面・セッション・Cookie、Action Cable も別、actor は `staff:` / `customer:`、パックも `staff_identity` / `customer_identity` に分ける~~（済。「認証と権限」）。~~Q1 窓口取引: 出金は利用者の「出金依頼」があるときだけ行員が処理（入金は現金持ち込みとして行員のみ）~~（**済**）。~~Q2 二人承認: 取消・組戻し・凍結の解除は「申請 → 別の行員が承認 → 実行」~~（**済**。どちらも「行員の権限: 窓口取引と二人承認」）。~~Q3 振込の差し止め: 予約振込と高額振込の保留を足し、実行前なら利用者は取消・行員は差し止めできる~~（**済**。「予約振込・高額振込の保留・取消と差し止め」） | O | `packs/banking`・`packs/admin`・`packs/customer`（承認は新しいパック） |
| ~~R~~ | ~~日本語のイベントビューア（RES Browser の代わり）: イベント名・ストリーム名を日本語に、中身を表で、correlation / causation の連鎖を図で。管理画面の中、行員だけ~~（済。「イベントビューア」。生中継・タイムマシン・レーン図も。利用者にも自分の口座だけの「わたしの出来事」。共通部品は `packs/event_lens`） | Q0 | `packs/event_viewer`・`packs/event_lens` |
| ~~S~~ | ~~WebSocket（Action Cable）を自分で書く: 窓口の整理券（番号札を取ると順番がライブで進み、呼ばれたらねこが知らせる）と、利用者と行員の窓口チャット（入力中の表示・在席表示）。自作チャンネル・presence・双方向。Q1 の窓口取引とつなげる~~（済。「窓口の整理券と窓口チャット」） | Q0, Q1 | `packs/counter` |
| T | デビットカード決済（二段階）: 商店での購入はまずオーソリ（お金を押さえる）→ 発送で売上確定 → キャンセルなら押さえを解除。残高と「使えるお金」を分ける。押さえの期限切れはジョブで解除 | D, Q0 | `packs/banking`（カード）・`packs/shop`（支払い） |
| U | 為替・外貨預金: 「ちゅ〜る ⇄ かつおぶし」など別の通貨の口座と両替。レートは数秒ごとに動き、WebSocket（Action Cable）で配信。両替の端数・手数料 | S | 新しいパック（例 `packs/fx`） |
| V | 不正検知: 「短時間に何度も出金」「深夜の高額振込」などのルールで自動凍結し、行員に通知。銀行のイベントを購読するだけで、銀行は検知を知らない（L のイベントの連鎖の実例） | L, Q0 | 新しいパック（例 `packs/fraud`） |
| W | カスタマーサポート: 利用者の問い合わせ（チケット: 受付 → 担当の行員 → 返信 → 解決）、よくある質問、ねこの自動応答（FAQ から候補を出す）。急ぎは S の窓口チャットへ引き継ぐ。返信は Action Text、メールでの問い合わせは Action Mailbox で受ける案 | Q0（S と一緒に） | 新しいパック（例 `packs/support`） |
| X | ねこの実況: 出来事が起きるたびに、ちゅーるが実況する（「いまオルカさんからミケさんへ 300 ちゅ〜る！」）。出来事を購読するだけの別の係にして、実況の文は出来事の種類ごとに決める | R | `packs/event_lens` か新しいパック |
| Y | ふせんの壁（イベントストーミング）: 出来事・命令・係を色のちがうふせんで時間順に並べた壁を、本物の記録から自動でつくる。流れの抜けや連鎖が一目でわかる | R | `packs/event_viewer` |
| Z | 「もしも」の世界: ある時点から出来事を差し替えたり足したりして、残高がどう変わったかを今の世界と並べて見る（記録は書き換えない。読み直すだけ） | R | `packs/event_viewer` |

並行の進め方（フェーズ1）: B+C / D / E→J / F+G+H を別々に進められる。
各自 `jj workspace add ../churu-bank-<名前>` で作業ディレクトリを分け、`bin/dev -p 300X` でポートも分ける
（DB は `storage/` 以下なので、作業ディレクトリごとに別になる）。
`config/routes.rb`・`db/schema.rb` は複数から触るので、最後にまとめてマージする。
