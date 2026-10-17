---
status: active
last-verified: 2026-10-17
---

# 0020: iOS アプリを再設計の見本どおりに作り直す（実装計画）

## 1. 目的と見本

iPhone アプリの UI を、Claude Design で作った再設計の見本（版 241・248 盤面。3 回の改訂済み）に合わせて作り直す。
機能は見本に描かれたものに限り、足さない。Mac 側の Control API は先に拡張済み（`mobile-api-extensions-contract.md` §8、ADR 0216。dev `54394e77`）。

見本の取り込み先は `ios/docs/specs/ClaudeDesign/`（macOS の `macos/docs/specs/ClaudeDesign/` と同じ置き方）。
元は `~/Downloads/phlox-ios-redesign 3/`。依頼文は `~/Downloads/phlox-ios-redesign-fix-request/`（1〜3 回目）。

## 2. 見本で決まっていること（要点）

| 領域 | 決定 | 主な盤面 |
|---|---|---|
| 見た目の土台 | Liquid Glass 採用（iOS 26）。iOS 18 は同じ配置の不透明な描き方 | Shell・Shell18・Detail・Detail18・DS |
| 色 | アクセントは白黒（#1D1D1F / #F2F2F4）、面の上は背景色。エージェント別の色・略号・紫ピンクのグラデは廃止。無応答は紫の注意色（status.stalled） | DS・DSDark |
| ロゴ | 実物のロゴ。Claude・Codex は副文字色の単色、Cursor は元の色 | DS |
| 状態 | アプリ内は文字だけ（起動中・実行中・承認待ち・質問あり・エラー・無応答・完了。待機は一覧に出さない）。記号はロック画面・ウィジェット・Live Activity・Dynamic Island だけ | List・GlanceCatalog |
| 下部 | タブは「セッション」「設定」の 2 つ＋離れた「新規チャット」ボタン。使用量タブは廃止 | Shell・List |
| 一覧 | 対応待ち → プロジェクトごと → その他。プロジェクトの見出しに常時「＋」。行は名前と右端の状態だけ。子セッションは字下げと案内線 | List*・ListSpec |
| 新規チャット | 10 種から選ぶ見出し（DotGothic16）、開くとキーボードが上がる、提案チップ 5 つ、エージェントを先に選ぶ段階は廃止 | Draft*・DraftSpec |
| 入力欄 | 2 段。1 段目は本文、2 段目は ＋・モデル・思考の強さ・権限、右にプロジェクト（新規のみ）と送信／停止。狭いときは思考の強さと権限を「…」にまとめる | Reply*・Draft* |
| モデル | 新規は 3 エージェントの全モデルを 1 つのシートで選ぶ（絞り込み・既定の印）。セッション画面はそのエージェントだけ | DraftModel*・ReplyModel |
| 権限 | Bypass Permissions・Full Access は確認のダイアログ、選択後のチップは赤 | DraftPerm*・ReplyPerm*・Dialogs P1〜P3 |
| 使用量 | 入力欄の下に残りのリング（Claude は 5h・7d の文字つき、Codex・Cursor はロゴとリング）。押すと残り % とリセットの吹き出し | Usage*・SetUseSpec |
| セッション画面 | 左上はホーム、端スワイプで戻るは残す。AI のアバター無し、返答は全幅、発言は右の吹き出し、Mac と同じカード。承認・質問は入力欄の上（承認は Claude Code と Codex だけ・4 ボタン） | Detail*・Chat*・Reply*・ChatSpec・ReplySpec |
| 廃止 | 端末画面と出力カード、使用量タブ、Codex の 4 択シート、俯瞰グリッド、独立した質問回答画面 | Revision20261017・ReviewMap |
| 表示できない会話 | 「このセッションは iPhone では表示できません。Mac で開いてください」だけ。入力欄・使用量・状態・停止は出さない | ChatUnsupported |

## 3. 前提と制約

- **配布対象は iOS 18.0**。Liquid Glass は `#available(iOS 26, *)` で分け、iOS 18 は Shell18・Detail18 の描き方にする。分岐は画面ごとに書かず、段階 1 で作る共通の部品 1 か所に閉じ込める。
- **XCUITest は実行しない**（ユーザーの全体ルール。`typeText` が Mac の入力ソースを増やすため）。既存の 29 本（`ios/PhloxMobileUITests`）は使わない。代わりの検証は 6 章。
- **DotGothic16** は iOS に未同梱。Mac と同じ ttf を同梱し `UIAppFonts` に登録する。ライセンス（SIL OFL。Mac 側に `OFL.txt` 同梱）の表示を iOS の「このアプリについて」等にも入れる。
- **古い Mac との互換**: 新しい取得口が 404・400 のときは「非対応」として該当のチップや一覧を隠し、今の動きに戻す（契約 §8.6）。
- **品質ゲート**: `.claude/verify.sh` は iOS を対象にしていない。iOS は 6 章のコマンドを正とする。
- **共有パッケージ**: `macos/Packages/DesignSystem`・`AgentDomain` を共有している。共有側を変えるときは macOS のテストも通す。

## 4. 着手前に決めたこと（2026-10-17 ユーザー回答）

| # | 論点 | 結論 |
|---|---|---|
| D1 | 見本の注記「一覧に出るプロジェクトはセッションが 1 つ以上あるものだけ」は、`GET /projects` ができたので古い | **出さない**（見本のまま）。空のプロジェクトは、新規チャットのプロジェクトのチップの選択肢には `GET /projects` で出す |
| D2 | 承認の見出し「承認待ち · {操作の種類}」。Codex の承認一覧（`/approvals`）に操作の種類が載っていない（Claude は質問の側から来る。段階 6） | **Mac を直す**。Codex の分だけ、承認一覧に操作の種類を足す小さな修正を段階 0 で行う |
| D3 | 見本の細かい説明の食い違い（ReplySpec の「他のエージェントと同じ 4 つ」、DraftSpec の N2 参照、改訂盤面の副題、思考の強さ・権限のメニューのダーク版） | 推奨どおり。実装は止めず、仕様書に正しい決定を書く |
| D4 | 見本との見比べに使う画像。盤面は Design キャンバスの中でしか正しく描けない | 推奨どおり。まず `macos/docs/specs/ClaudeDesign/support.js` を使って盤面を手元で描けるか試す。描けなければ Design キャンバスの Share › Export で画像を書き出してもらう（ユーザー作業）。それも無理なら盤面のソースの寸法・文言との突き合わせで代える |
| D5 | 体制 | 取りまとめ Opus 5.5 high、実装 Codex gpt-6.1-sol medium か gpt-6-luna max（2026-10-17 ユーザー指示）、検証 Codex gpt-6-luna high |
| D6 | 既存の UI テスト（`PhloxMobileUITests` 29 本。`ScreenshotTests`・`doc/screenshots/`・`scripts/compare-screenshots.py` を含む）は XCUITest なので実行できない | **削除する**。描画テストに置き換える |

## 5. 段階

各段階の終わりに 6 章の検証を通し、段階ごとにコミットする（コミットとマージはユーザーの承認後）。レビューは段階ごとではなく、段階 8 でまとめて 1 回行う（リポジトリの規約）。

### 段階 0 — 資料と見本、検証の土台（S）

- 見本 248 盤面を `ios/docs/specs/ClaudeDesign/` に取り込む（取り込み済み）。盤面が節番号で引いている `ios/docs/specs/ui-feature-inventory.md` も取り込み、「再設計前の棚卸し」として `status: superseded` にする。dev にだけある `ios/Design/claude-design-prompts.md`・`ios/docs/guides/install-ad-hoc-over-tailscale.md` は再設計に要らないので取り込まない（ユーザー判断）。
- D2: Mac の Control API の承認一覧（`ApprovalDTO`）に操作の種類を足す（省略可の項目・古いクライアント互換）。契約 §8 と ADR 0216 に追記する。
- 仕様書 `ios/docs/specs/redesign-2026-10.md` を新しく書く: 2 章の決定・受け入れ基準・盤面との対応・D1〜D3 の結論。
- ADR を起こす（番号は 0043 から）: Liquid Glass 採用と iOS 18 の描き方／端末画面の廃止／使用量タブの廃止と入力欄の下のリング／Mac と揃える方針（色・ロゴ・状態・一覧・新規チャット・入力欄）／XCUITest をやめ描画テストへ移すこと。
- 描画テストの土台を作る: 今はアプリに載る単体テストのターゲットが無い（UI テストだけ）。`project.yml` に新しい単体テストのターゲットを足し、`ImageRenderer` で画面を 428×926・375×667・ダーク・Dynamic Type 最大で書き出す（macOS の `DesignSnapshotRenderTests` と同じ考え方。環境変数を立てたときだけ書き出す）。
- `run-simulator.sh --screen` が使う見本のデータに、新規チャット・使用量のリング・表示できない会話・承認のカードの場面を足す場所と方法を 6.1 に記録した（場面そのものは各段階で画面と一緒に足す）。
- 完了: 資料が揃い、空の描画テストが動いて画像が書き出せる。

### 段階 1 — 土台の部品と、廃止する機能の削除（M）

- トークン: アクセントを白黒にし `accentOnFill` を足す。`campAgentColor`・`campAccentBright`・`campAttention`・`DSGradient.brand` を消す。`status.stalled`（紫）を足す。状態の語を揃える。
- 共通の部品: Liquid Glass のバー・ボタン（iOS 26 と iOS 18 の分岐をここに閉じ込める）、ロゴ（共有の `AgentBrandIcon` を単色・元の色で使い分ける）、DotGothic16。
- 機能の削除（削除する機能ごとに、そのテストも消す。テストを弱めて通すのではないことを作業記録に書く）:
  - 端末画面: `TerminalScreenIOS` モジュール・出力カード・`SessionTerminalLive` の UI テスト。
  - 使用量タブ: `Features/Usage/UsageView.swift` と関連テスト。
  - 俯瞰グリッド: `Features/SessionsOverview/`。
  - Codex の 4 択シート: `CodexApprovalSheet`。
  - 独立した質問回答画面: `Features/ChatAnswer/` と `Route.chatAnswer`（質問はセッション画面のカードに統合）。
  - UI テスト: `PhloxMobileUITests` ターゲット（D6 の結論による）。
  - 呼び出し元の無い部品: `DSVoiceInputController`（音声入力は ADR 0018 で撤去済み）・`DSFAB`・`DSTextField`・`DSConnectionIndicator`・`DSFixedBottomCTA`・`DSCampAgentBadge`。`Info.plist` のマイクと音声認識の権限文。
- 完了: ビルドが通り、残るテストが green。消したものの一覧が作業記録にある。

### 段階 2 — API の配線（M）

- 先に Mac 側の追加を行う（仕様書 U-3・U-8）: `GET /sessions` に無応答・終了・未読・親子関係、質問にツール使用の許可であることとツール名。省略可の項目にして古いクライアント互換を保ち、契約 §8 と ADR 0216 に追記する。

- `GET /projects`、`GET /agents/{kind}/settings`、`GET`・`PATCH /sessions/{id}/settings` の追加項目、`POST /sessions` の `effort`・`permission`・`planMode`、質問の `allowsSessionScope`（回答 `"AllowForSession"`）。
- 409（変更中）・425（準備前）・404・400 の扱い。古い Mac では非対応として隠す。
- 完了: 取得口ごとの通信の形・エラー・互換のテストが green。

### 段階 3 — 一覧と下部のナビゲーション（M）

- 自前のタブバーを、タブ 2 つ＋離れた「新規チャット」ボタンに作り替える（iOS 26 は Liquid Glass、iOS 18 は Shell18）。
- 一覧: 対応待ち・プロジェクトごと（セッションのあるプロジェクトだけ。D1）・その他。見出しの「＋」・閉じたときの内訳・行の状態の文字・未読の太さ・実行中の光の帯（Reduce Motion で止める）・子セッション。
- 完了: List*・Shell* の盤面と描画テストの画像が一致する。

### 段階 4 — 入力欄と使用量のリング（L）

- `DSInputBar` を 2 段に作り直す。チップ（モデル・思考の強さ・権限・プロジェクト）、狭いときの「…」、送信／停止、添付のサムネイル。Haiku では思考の強さを出さない。
- 強い権限の確認ダイアログと赤いチップ、変更失敗の知らせ。
- 入力欄の下の使用量のリングと、押したときの吹き出し。残り 20% 未満は注意の色、取得できない・期限切れは灰色。VoiceOver は行を 1 つとして読む。
- 完了: Reply*（入力欄）・Usage* の盤面と一致し、入力欄の状態ごとのテストが green。

### 段階 5 — 新規チャット（M）

- 下書きの画面を作り替える: 見出し 10 種・開くと入力欄にフォーカス・提案チップ・プロジェクトのチップ（初期値は前回使ったもの。「＋」から開いたらそのプロジェクト）・全モデルのシート・作成 → 準備待ち → 送信 → セッション画面。失敗したら本文を戻す。
- 完了: Draft* の盤面と一致する。

### 段階 6 — セッション画面（L）

- 上部（ホーム・名前・「…」）、端スワイプで戻る。
- 会話: アバター無し・全幅の返答・右の吹き出し・Mac と同じカード（コマンド・ツール実行・ファイル変更・思考）・実行中の要約・無応答（紫と「中断」）・ターンの終わりの行・エラー・長押しのメニュー。
- 入力欄の上の承認・質問のカード。誤承認の防止（出現直後の無効時間など）は保つ。
- 承認のカードは 1 つの部品で、2 つの経路から作る（Mac の `ChatReplyApproval.swift:144-162` と同じ組み方）:

  | | Codex | Claude Code |
  |---|---|---|
  | 届く経路 | `GET /approvals` | `GET /sessions/{id}/question`（ツール使用の許可の質問。`allowsSessionScope` 付き） |
  | 許可 | `POST /approvals/{id}` accept | 質問に `"Allow"` |
  | このセッション中は許可 | acceptForSession | 質問に `"AllowForSession"`（`allowsSessionScope` が true のときだけ出す） |
  | 拒否 | decline | 質問に `"Deny"` |
  | キャンセル | cancel | ターンの中断（`POST /sessions/{id}/interrupt`。Mac の質問カードの「閉じる」と同じ） |
  | 見出しの操作の種類 | 今は届かない（D2） | 許可の質問に載るツール名から作れるかを、この段階の最初に確かめる |

- 今の iOS は Claude の許可を質問のカード（`UserQuestionCard`）で出している。この経路を承認のカードへ移す。
- 表示できない会話の画面。
- `SessionDetailViewModel`（1030 行）は画面に結び付いた処理が多いので、この段階で表示用の状態と通信の処理を分ける。
- 完了: Detail*・Chat*・Reply*（承認・質問）の盤面と一致する。

### 段階 7 — アプリ外の表示（S）

- ウィジェット・Live Activity・Dynamic Island・通知の色を新しい配色に合わせる（無応答の紫、記号はここだけ残す）。
- 完了: Glance* の盤面と一致する。

### 段階 8 — 見比べ・まとめのレビュー・資料の仕上げ（M）

- 全盤面を描画テストの画像と見比べ、差を直す。
- 作業全体を 1 回まとめて独立レビューする。
- 仕様書・ADR・アーキテクチャ文書を実装に合わせ、作業記録を残す。

## 6. 検証の方法

| 検査 | コマンド（テストは `~/.agents/scripts/compact-test` 経由） |
|---|---|
| 単体テスト | `swift test --package-path ios/Packages/PhloxKit` |
| アプリとウィジェットのビルド | `make -C ios generate` のあと `xcodebuild build -scheme PhloxMobile -destination 'generic/platform=iOS Simulator'`（PhloxWidget は埋め込みで一緒にビルドされる）。`make build` は iPhone 16 のシミュレーターを探すので、無い機械では動かない |
| 描画テスト（段階 0 で作る） | シミュレーター上の単体テストを `xcodebuild test -only-testing:<描画テスト>` で実行し、画像を `.verification/` に書き出す |
| 実機に近い確認 | `ios/scripts/run-simulator.sh --screen <名前>` で起動し `xcrun simctl io booted screenshot`。文字の入力は行わない。Makefile のシミュレーターは iPhone 16（393×852）で、盤面（428×926・375×667）とは大きさが違うので、寸法の見比べは描画テストの画像で行う |
| 共有パッケージを変えたとき | macOS の該当パッケージを `macos/scripts/run-swift-tests.sh <パッケージ>` で（DashboardFeature・SessionFeature は `swift test` を直接叩くと並列で詰まる。ADR 0170）。正本の対象外のパッケージ（ControlServer・AppBootstrap）は `swift test --package-path` |
| lint | `make -C ios lint`（`scripts/lint-raw-values.sh`） |

実機（iPhone）での最終確認はユーザーに依頼する（Tailscale 経由の配布手順は dev 側で作業中の手順書を使う）。

### 6.1 描画テスト（段階 0 で作成）

- 実行: `PATH=/opt/homebrew/bin:$PATH make -C ios snapshot SNAPSHOT_SIMULATOR_ID=<UDID>`。スキーム `PhloxMobileSnapshots`（UI テストを含まない）で `PhloxMobileSnapshotTests` だけを走らせ、`<worktree>/.verification/ios-redesign/snapshots/` に `<画面>-<幅>x<高さ>-<light|dark>[-ax5].png` を書き出す。`PHLOX_DESIGN_SNAPSHOTS=1` が無いときは何も書かずに成功する。`SNAPSHOT_SIMULATOR_ID` を省くと、利用できる最初の iPhone のシミュレーターを使う。
- 描き方: `ImageRenderer` は `NavigationStack` を描けず禁止マークになったので、`UIWindow` に `UIHostingController` を載せて `drawHierarchy` で撮る（画素の検査で中身の有無を確かめてから書き出す）。
- データ: `AppEnvironment.uiTesting(scenario:screen:)`（`run-simulator.sh --screen` と同じ見本のデータ）を `@testable import PhloxMobile` で使う。
- 安全領域と倍率（段階 1 で足した）: 428×926 は上 47・下 34 の安全領域で 3 倍、375×667 は上 20・下 0 で 2 倍に書き出す。共通の部品の見本 `components-428x926-<light|dark>-ios<26|18>.png` は OS ごとに描き分けが違うので、名前に OS の版を付ける（ほかの画面は付けない。両方の OS で撮るときは、後に撮った方で上書きされる）。
- 段階 3〜6 の場面（新規チャット・使用量のリング・表示できない会話・承認のカード）の足し方: `ios/App/UITestingSupport.swift` の `UITestingSupport.Screen` に case を足し、`ios/App/AppEnvironment+UITesting.swift` の `environment(for:)` に見本のデータ、`ios/App/UITestingNavigator.swift` の `applyNavigation` に遷移を書く。`run-simulator.sh --list-screens` と描画テストの画面の一覧に同じ名前で足す。空の入口は今は足さない（中身の無い case を残さないため。各段階で画面と一緒に足す）。廃止する `spawn`・`chatAnswer`・`codexApproval`・`spawnError` は段階 1 で消す。

### 6.2 盤面の画像の書き出し（D4。2026-10-17 に試して描けた）

1. 配信用のディレクトリを作る（リポジトリの見本は変えない）: `ios/docs/specs/ClaudeDesign/*` をシンボリックリンクで並べ、`macos/docs/specs/ClaudeDesign/support.js` を写す。
2. 盤面はロゴを `/_blob/<hash>` で引くので、同じディレクトリに `_blob/66b7f1b7606ba770d37ef565d21126a7`→`logos/logo-claude-mask.png`、`_blob/9b2e356e19d43dd099a2a01181b303ba`→`logos/logo-codex-mask.png`、`_blob/02f5e276fd254ff6f2137701b1097708`→`logos/logo-cursor.png` のリンクを置く（対応は `DS.dc.html` の `.lg-claude`・`.lg-codex`・`.lg-cursor`）。
3. そのディレクトリで `python3 -m http.server <port> --bind 127.0.0.1`（`file://` では `dc-import` が親を読めない）。
4. Playwright で表示域を盤面の `$preview`（428×926・375×667）にして開き、表示域のスクリーンショットを撮る。Google Fonts（Noto Sans JP・JetBrains Mono）はネットワークから読む。
5. 書き出し例: `.verification/ios-redesign/design-boards/`（`ListSE-375x667.png`・`ReplyCodex-428x926.png`・`DraftDark-428x926.png`）。終わったらサーバーを止める。

## 7. 危険と対策

- **既存テストの大量の書き換え**: `FeaturesTests`（81 ファイル）は画面の構造に結び付いたものが多い。消した機能のテストは機能と一緒に消し、残す機能のテストは振る舞いの検証に寄せて直す。期待値を下げて通すことはしない。
- **Liquid Glass の API**: Xcode と iOS 26 SDK の版で使える API が違う。段階 1 の最初に、手元の Xcode でビルドできる範囲を確かめる。
- **入力欄とセッション画面が大きい**: 段階 4・6 は作業を小さく分け、1 回の委譲を 1 つの部品に限る。
- **見本で描けていない状態**: 見本に無い状態に当たったら、勝手に作らず仕様書に論点として書き、ユーザーに確かめる。

## 8. 対象外

- Mac 側の変更（D2 の承認の種類と、仕様書 U-3・U-8 の項目の追加を除く）。
- iPad・横向き・新しい機能。
- 見本の盤面そのものの修正（D3）。
