---
status: active
last-verified: 2026-10-18
---

# アーキテクチャ概要（現行）

> **このファイルの役割**: Phlox-mobile が **今こう動いている** 構成・データフロー・主要 I/F の参照。
> **書かないもの**: なぜその方式か（→ [adr/](../adr/)）・要件（→ [specs/](../specs/)）・作業経緯（→ [docs/delivery/](../../../docs/delivery/)）。

## パッケージ構成

アプリ本体（`App/`）＋ Swift Package `Packages/PhloxKit` ＋ WidgetKit 拡張ターゲット `PhloxWidget/`（`ios/project.yml` の `PhloxWidget` app-extension ターゲット、`PhloxCore` のみに依存。→ [共有ストレージとウィジェット拡張](#共有ストレージとウィジェット拡張-phloxwidget)）。PhloxKit は次のモジュールに層分けされる。

| モジュール | 役割 |
|---|---|
| `PhloxCore` | ドメイン型（`Session`・`ChatMessage`・`TurnUsage`・`MessagesDelta`・`SendRequest`/`SendAttachment`・`AgentModels`/`SessionModelOption`・`CLIUsage`/`UsageBucket`/`CLIUsageState`・`PhloxError` 等）と `PhloxAPI` プロトコル。UI・ネットワークに非依存。`Shared/` サブディレクトリに `SharedSessionStore`/`SharedSessionWriter`（App Group 経由でウィジェット拡張と状態共有、→ [共有ストレージとウィジェット拡張](#共有ストレージとウィジェット拡張-phloxwidget)） |
| `PhloxNetworking` | `PhloxAPIClient`（`PhloxAPI` の HTTP 実装）・`HostTrustPolicy`・DTO ↔ ドメイン変換 |
| `DesignSystemIOS` | 再利用 UI 部品（チャットバブル・マークダウン・ロゴ・トークン）。色は `IOSColor`、状態の語は `IOSStatusVocabulary`、Liquid Glass と iOS 18 の描き分けは `glassSurface(_:)`、左上のホームは `navigationStackHomeBackButton()`（→ [ADR 0043](../adr/0043-liquid-glass-with-ios18-opaque-fallback.md)・[ADR 0048](../adr/0048-home-button-is-the-system-back-button-with-a-house.md)） |
| `Features` | 画面ごとの `@Observable` ViewModel と SwiftUI View |

### `Features` サブモジュール

| サブモジュール | 現行構成 |
|---|---|
| `Features/ConnectionSettings` | QR で接続先とトークンを適用し、接続先の読み取り表示・疎通テスト・再接続を提供する。到達性は `ReachabilityMonitor`（`NWPathMonitor`＋`/sessions` healthCheck）が保持し、QR ペアリング完了・手動「再接続を試す」で `refresh()` により即再判定する（→ [ADR 0019](../adr/0019-reachability-on-demand-refresh.md)）。QR 適用後は一覧の取得成功まで接続オーバーレイを保ち、端末名・接続先・経過秒数を表示する。20 秒で未応答なら C1 の説明・確認項目・再試行・閉じるを表示する（→ [ADR 0021](../adr/0021-connecting-overlay-gated-on-session-list-load.md)） |
| `Features/Pairing` | `QRScanScreen`、`PairingApplyViewModel`、`QRImageDecoder`。QR から読み取った host・port・token を検証して接続設定へ一括適用する |
| `Features/Settings` | `@Observable` の `AppSettings` と `AppSettingsStoring`。`UserDefaults` 永続化の Face ID（**既定オフ** → [ADR 0017](../adr/0017-face-id-launch-gate-default-off.md)）、通知（既定オン）、外観（`AppearancePreference.system/light/dark`）と About を提供する |
| `Features/SessionList` | 一覧画面。`SessionListProjection` が対応待ち 4 種（承認待ち・質問あり・エラー・無応答）、`GET /projects` 順のプロジェクト欄、未割当の「その他」、同じプロジェクト内の親子木、折りたたみ時の状態内訳を View 非依存で作る。古い Mac がプロジェクト一覧を返さない場合は、セッションが届いた順で欄を並べる。対応待ち行はプロジェクト欄に重ねない。行は名前と状態語だけで、未読名を semibold、実行中名に Reduce Motion 対応の 1 回の光の帯を表示する。子は既定で閉じ、開閉状態は `SessionListView` のメモリだけに保つ。`SessionListView` は一覧・スケルトン・接続判定・空・オフライン・取得エラーを表示する。3 秒ごとの一覧取得はセッションだけを更新し、引っ張って更新ではセッション・プロジェクト・使用量を並行して再取得する。到達性が未判定の間は読み込み表示を続け、判定後に必要なオフライン表示へ移る（→ [ADR 0027](../adr/0027-session-list-probe-before-offline.md)） |
| `Features/Spawn` | wave-4 で廃止（ソースファイル削除、ディレクトリのみ残置）。新規セッション作成は一覧の「新規チャット」・プロジェクトの「＋」から `Features/NewChat` の専用画面へ遷移する（→ [ADR 0008](../adr/0008-spawn-screen-to-draft-compose.md)） |
| `Features/NewChat` | 見出し・提案・モデル・設定・プロジェクト選択と初回送信を `NewChatViewModel` が保持する。`GET /agents/{kind}/models`・`GET /agents/{kind}/settings`・`GET /projects` を使い、旧 Mac ではセッション一覧からプロジェクトを組み立てる。送信時は spawn → ready → send を行い、失敗時の本文・添付回復は実セッション画面へ渡す（→ 仕様 AC-5-1〜15） |
| `Features/Usage` | `AppRoot` が `UsageViewModel` を 1 つ生成し、環境値でセッション詳細・新規チャットと一覧へ渡す。`load()` は `GET /usage` を呼び、取得中と失敗後も前の値を保持する。`UsageRingPresentation` が残り・枠順・リセット書式・VoiceOver 文言を共有し、`UsageRingRow` が入力欄下の 44pt の行とポップオーバーを描く。使用量タブの画面は再設計で消した（→ [ADR 0045](../adr/0045-usage-ring-under-the-input-replaces-usage-tab.md)） |
| `Features/AppShell` | 下部固定タブバーの状態機械。`AppTab`（`.sessions/.settings` の 2 種。wave-4 で `.overview`（→ [ADR 0007](../adr/0007-remove-overview-tab.md)）、再設計で `.usage`（→ [ADR 0045](../adr/0045-usage-ring-under-the-input-replaces-usage-tab.md)）を削除）と `AppShellViewModel.selectTab(_:)`（現在は単純な選択更新のみ。旧・俯瞰タブ再選択トグルは削除済み） |

## アプリルートの設定反映

### ペアリング・エラー・設定（再設計段階 8a）

`AppRoot` は復元処理とロック解除が完了するまで `phlox://pair` を保留する。QR 成功時に受け取った Mac 名を接続オーバーレイへ渡し、初回は一覧の取得成功で閉じる。設定からの再接続は設定画面に留まる。QR のパース失敗・カメラ不可・画像内 QR 不在・疎通失敗は `QRScanCopy` / `PairingCopy`、初回 20 秒失敗は `ConnectFailure`、API 失敗は `PhloxError.presentation` から表示する。各表示は見出し、原因、次の操作、等幅の技術値の順で組み、HTTP 429 は `isNeutral` を引き継いで無彩色にする。

`SettingsView` の区画順は接続 → 通知 → セキュリティ → 外観 → このアプリについて。セキュリティ欄は Face ID / Touch ID の端末名に合わせ、使用量用の設定欄は置かない。DotGothic16 のライセンス行と本文は「このアプリについて」に残す。

### 外観のライブ反映

`AppRoot` は `AppSettings.appearance` を監視し、`rootContent` に `.preferredColorScheme` を適用する。同時に `phlox.theme` を `AppearancePreference.themeID` へ同期し、`.id(activeThemeID)` で `rootContent` を再描画する。`system` 選択時は `@Environment(\.colorScheme)` に追従してライト／ダークのテーマ ID を切り替える。

### Face ID 状態機械

`AppModel.initialAuthState` が起動時の認証状態を決め、`shouldRelock` が背景復帰時の再ロック要否を管理する。`AppRoot` は `scenePhase` が `.background` へ遷移した時に再ロックし、Face ID 設定を無効にした時はロック状態を解除する。**Face ID 設定の既定はオフ**（`UserDefaultsAppSettingsStore.faceIDEnabled` の未設定フォールバックは `false`＝新規インストール時は起動ロックしない。設定で ON にしたときだけ起動ロック・背景復帰時の再ロックが働く。`initialAuthState`/`shouldRelock` は `faceIDEnabled` を明示引数で受けるため既定値変更の影響を受けない → [ADR 0017](../adr/0017-face-id-launch-gate-default-off.md)）。

## アプリシェル（下部ナビゲーション、`Features/AppShell`）

`AppRoot`（`ios/App/AppRoot.swift`）は標準の SwiftUI `TabView` を使い、`AppTab`（`.sessions`・`.settings`）ごとの
`NavigationStack` を切り替える。OS ごとの共通表示は `DesignSystemIOS.DSPlatformTabView` にまとめる。
iOS 26 は標準のガラスタブ・`tabViewBottomAccessory`・`tabBarMinimizeBehavior(.onScrollDown)` と独立した
`Tab(role: .search)` の操作を使う。iOS 18 は標準タブバーと `safeAreaInset` を使い、一覧の大見出し右の新規チャットだけ
`DSLegacyNewChatButton` で足す（→ [ADR 0049](../adr/0049-standard-tabview-for-navigation.md)）。

`Features/AppShell.SessionNavigationState` は対応待ち 4 状態の件数・先頭・アクセサリ表示を決める。
対応待ちの欄・バーの先頭・長押しメニューは `SessionAttentionQueue.ordered` を共用し、Mac の `AttentionQueue.ordered` と同じ `statusEnteredAt` の古い順にする。時刻なしは末尾、同時刻（時刻なし同士を含む）は Mac からの受信順を保つ。プロジェクトと「その他」の閉じた内訳は、その欄の表示行と子孫だけを数え、対応待ちへ移した行を含めない。内訳は見出し右端の「＋」の左へ寄せる。
`AppRoot` の選択 Binding は、新規チャット操作を compose へ送り、同じタブの選択を受け取った場合に
一覧のルート復帰と先頭スクロール、設定のルート復帰を行う。SwiftUI が同一選択の再タップで Binding setter を呼ぶかは
公開仕様に記載がなく、実操作で未確認（→ ADR 0049）。

## ネットワーク層（`PhloxNetworking`）

`PhloxAPIClient` が `PhloxAPI` プロトコルを実装する。エンドポイントは Mac 側 Phlox サーバーの REST。動的パスセグメント（sessionID・approvalID）は `percentEncodedPathSegment` で個別にエンコードしてから `components.percentEncodedPath` へ組み立てる（二重エンコードと不正文字での `percentEncodedPath` setter クラッシュを回避）。

主要エンドポイント（`sessions/{id}` 基点。API 拡張分は契約 v1 — [../specs/mobile-api-extensions-contract.md](../specs/mobile-api-extensions-contract.md)）:

| メソッド | HTTP | パス |
|---|---|---|
| `listSessions` / `spawn` | GET / POST | `sessions` |
| `send`（text＋images） | POST | `sessions/{id}/messages` |
| `messages` | GET | `sessions/{id}/messages` |
| `messagesDelta` | GET | `sessions/{id}/messages?since=<cursor>&wait=<ms>` |
| `interrupt` | POST | `sessions/{id}/interrupt` |
| `usage` | GET | `sessions/{id}/usage` |
| `waitUntilReady` / `remove` | GET / DELETE | `sessions/{id}/ready` `sessions/{id}` |
| `approvals` / `respond` | GET / POST | `approvals` `approvals/{id}` |
| `agentSettings` / `projects` | GET | `agents/{kind}/settings` `projects`（契約 §8.2・§8.5。旧 Mac の 404 は非対応として nil） |
| `sessionSettings` / `updateSessionSettings` / `setModel` | GET / PATCH / POST | `sessions/{id}/settings` `sessions/{id}/model`（契約 §6・§8.3〜§8.4） |
| `agentModels(kind:)` | GET | `agents/{kind}/models`（契約 §7.3・spawn 前モデル一覧） |
| `cliUsage()` | GET | `usage`（契約 §7.4・アカウント単位使用量） |

`GET /sessions` は Mac が返す配列順を保持し、`backend`・無応答・未読・親子・状態変更時刻を `Session` に写す。状態語は共有 `SessionDisplayState.resolve` を通す。新規セッションの `effort`・`permission`・`planMode` は未指定なら body から省略する。旧 Mac で未対応の agent settings / projects は nil、設定更新の旧 Mac 応答は `PhloxError.unsupported` として呼び出し側へ返す。

**前方互換**: `messages` 系はメッセージ DTO の未知 `type` を `toDomain` が `nil` にし `compactMap` で除外する。差分ポーリングで 404/501 を受けたら `messages()` 全量取得へフォールバックする（旧サーバー互換）。

**信頼ポリシー**: `HostTrustPolicy` が `*.ts.net`（Tailscale MagicDNS、ラベル境界を検証）とプライベート IP レンジ（IPv4 は4オクテット厳密パース＋CIDR ビット境界）にのみ `Authorization` ヘッダを付与する。平文 HTTP でのトークン露出を信頼済みネットワークに限定する（→ [doc/adr/0003-plaintext-http-tailscale-client-guard.md](../adr/0003-plaintext-http-tailscale-client-guard.md)）。

## セッション詳細のデータフロー（`Features/SessionDetail`）

`SessionDetailViewModel`（`@MainActor @Observable`）がチャット面の状態を持つ。

- **画面構成**（wave-6）: 承認リクエスト（`approvalSection`）＋会話（`transcriptSection`。構造化チャットだけを描く。端末画面と出力カードは再設計で消した → [ADR 0044](../adr/0044-remove-terminal-screen-and-unsupported-sessions.md)）＋入力バー（`inputBarSection`）で構成される。wave-5 まで存在したヘッダーカード（エージェントバッジ・ステータスチップ・「エージェント名 + 開始時刻」のメタ行を1枚のカードにまとめた表示）は撤去され、代替表示は無い。
- **メッセージ取得**: 起動時 `messages()`、以降は `messagesDelta(since:cursor)` でカーソル前進しながら差分採用（`adoptMessagesFromDelta`＝スナップショットなら置換・差分なら追記、cursor 更新）。一時失敗では表示を消さない。
- **送信**: `SendRequest`（text＋`[SendAttachment]`）。送信完了バナー（旧 `SendState.sent`）は廃止。
- **停止**: `canInterrupt` が真のとき `stop()` が `interrupt` を呼ぶ。409（既に停止/完了）はボタン無効化で吸収。
- **usage**: 非実行中セッションを開いた時と running→idle の遷移時に `usage()` を取得し `turnUsage` を持つ。会話内の `turnCost` は届いた位置ごとに行を描く。最新ターンの行にだけコンテキスト使用量を併記し、そのターンに `turnCost` が無い場合は契約 §4 の `costUSD` を補う。入力・出力 token は表示しない。
- **サブエージェントの行は押せない（U-21）**: `SessionDetailSubAgentCard` が `DSChatCodeCard` にタスク名と状態を表示する。見出しは開閉せず、「›」も詳細案内も付けない。詳細画面・一覧と詳細会話の取得・遷移用 ID は廃止した。Mac の API（契約 §2・§3）は残す。
- **モデル選択**: `sessionSettings()` が `availableModels` を返した時だけモデルチップ（選択中モデルの表示名）を出し、タップでモデル選択シート（`ModelPickerSheet`）を開いて `setModel` を呼ぶ。非対応セッション（codex 等）・取得失敗時はチップ非表示に劣化（画面全体は壊さない）。チップは **入力欄内（`DSInputBar` の `modelSelector` スロット）と右上メニューの2箇所**から到達できる（wave-4 で入力欄チップを復活 → [ADR 0010](../adr/0010-restore-inline-model-selector-chip.md)）。
- **添付**: `addAttachments()` が最大4枚・各20MB・合計80MB を検証（超過はバッチ全体を拒否）、`normalizeAttachment` が magic-byte で実体判定し 元画像を保持する。送信前に共有ImageAttachmentKitをメインスレッド外で実行し、HEIC等の形式変換・解像度を保つ容量の調整を行う（送信用は各3.75MB・合計15MB）。プレビューは一度だけ downsample して `previewData` にキャッシュ。送信した添付は、送信テキストで送信後スナップショットのユーザーメッセージへ突き合わせる（`SessionAttachmentReconciler`）。`message.id` ごとにプレビュー画像データを保持し、`SessionDetailUserMessageBubble` の本文上に 56pt サムネイルを描く（サーバ/ワイヤ不変・クライアント完結 → [ADR 0020](../adr/0020-chat-attachment-badge-client-side.md)）。
- **右上メニューの presentation**（wave-5）: モデル変更シート・rename アラートは `SessionDetailViewModel` の `private enum MenuPresentation { case modelPicker, rename }` を単一ソースとして排他管理する（`isModelSheetPresented`/`isRenamePresented` はこの enum への computed property）。`.sheet` は `.alert` とは別の View 階層（チャットスクロール＋`inputBarSection` を含む内側 VStack）に付与され、同一 View への複数 presentation 併置を避ける（→ [ADR 0013](../adr/0013-session-detail-menu-presentation-single-source.md)）。
- **返答エリア**: Codex の `GET /approvals` と Claude Code の単一項目 `userQuestion`（`toolName` 付き）を `ReplyApproval` にまとめ、同じ承認カードで扱う。Cursor には承認を表示しない。承認は質問カードより上、通常の pending question はその下に置く。
- **メッセージ表示**: reasoning・command・fileChange・回答済み／期限切れ userQuestion は見出しから開閉し、`expandedMessageIDs`（`ChatMessage.id` キー）でポーリング後も状態を保持する。pending question は transcript から外して入力欄上へ置く。user は添付があれば本文の上にサムネイルを含む右寄せ吹き出し、agent はアバターなしの全幅 Markdown、error は三角アイコン付き淡赤面、turnCost は各項目の位置に描く。
- **チャット表示の規則は macOS と共有する**（→ [ADR 0041](../adr/0041-chat-render-rules-shared-via-chatrenderkit.md)）: 表示の純粋計算は共有ターゲット **`ChatRenderKit`**（`macos/Packages/AgentDomain` 内・Foundation のみ）にあり、macOS と iOS の双方がこの 1 実装を呼ぶ。内訳は `ChatDiffClassifier`（diff の行分類・`@@` からの行番号採番）／`ChatCodeTokenizer`（Swift・シェル）／`ChatCommandToolLabel`（先頭トークンを既知ツール名と完全一致、外れは `Bash`）／`ChatFileChangePresentation`（動詞・増減行数・見出し）／`ChatReasoningPresentation`／`ChatCommandGroupTitle`（見出し＝最後のコマンド原文・60 字クランプ、コマンドが無ければ `"ツール実行 ×N"`）。
  - **器**は `DSChatCodeCard`（枠線・角丸・背景・クリップのみ）。ツール実行グループ自体は器を持たず、見出しと展開状態だけを持つ（入れ子で枠が二重にならないため）。
  - **ファイル変更**は `SessionDetailFileChangeCard` が `SessionDetailDiffCodeViewData`（純関数）から描く。行番号は根拠があるときだけ出し（1 つも確定しないなら番号列の幅 0）、hunk 行・`---`/`+++`・no-newline 注記は表示しない（採番のデータとしては保持）。既定は折りたたみ（行数に依存しない）、見出しは `<動詞> <ファイル名> +A -D`、カード内にフルパス 1 行。**コピーは元の diff 全文**。長い行は**横スクロール**で到達でき、パス見出しは横スクロールの外に置く。
  - **Reasoning** は「思考」ラベルだけを既定で閉じて描く。開くと `text.secondary` の本文を表示する。
  - **行の種類**は `ChatRowKind.forMessage(_:)` に 1 本化し、セッション詳細がこれで分岐する（`default:` を置かず、メッセージ種別の追加はコンパイルエラーになる）。
  - **カード共通部品**: 会話カードは `bg.card`・1pt の枠・角丸 8、実行中だけ枠を 1.5pt にする。見出しは 44pt 以上。単独コマンドはコマンドカード、連続ツールは「ツール実行 ×N」の親カードと個別の子カード。出力は 20 行で区切り、残りの行数とセクションコピーを示す。ファイル変更は 1 ファイルごとにカードを分ける。閉じた思考と質問カードにも共通枠を使う。
  - markdown のコードブロック用ハイライタ（`DesignSystemIOS.CodeHighlighter.tokens(for:language:)`）は据え置きで、`ChatRenderKit` の Swift トークナイザとは別実装（意図的な二重。→ ADR 0041）。
- **ツールコールの集約行**（→ [ADR 0026](../adr/0026-ios-single-toolcall-grouped-row.md) / [ADR 0038](../adr/0038-command-group-cost-bounding.md)）: `SessionDetailToolCallGrouping`（純関数）が transcript を描画単位 `SessionDetailChatBlock`（`single` / `commandGroup`）へ畳む。**連続する `.command` は1件以上で必ず `commandGroup`**（id = グループ先頭 message の id・順序保存）になり、`.command` 以外はグループ境界かつ `single`。`commandGroup` は `SessionDetailToolCallGroupRow` が**最後のコマンド原文**の見出し 1 行（＋タイトル直後のシェブロン。器は持たない）として描画し、タップで各コマンド行を `SessionDetailCommandCard`（ツール名ラベル＋`$ <コマンド>`＋出力・枠線付き）として展開する。見出しがコマンド原文でなく `"ツール実行 ×N"` になるのは、コマンドが 1 件も無いグループのフォールバックだけ（→ [ADR 0041](../adr/0041-chat-render-rules-shared-via-chatrenderkit.md)）。展開部の行は「出力が空かつ実行中でない」ものを除外するが、**`items.count == 1` のときは除外しない**（唯一の行を消すとどのコマンドが走ったか分からなくなるため）。全件空出力かつ非実行中の**複数件**グループはカード自体を描画しない。`scrollTargetID` は個別 message の id をその所属グループの id へ解決する。**窓境界は必ずブロック境界に来るため部分ブロックは生じない**（ADR 0037 で旧・境界分割処理は削除）。macOS も ADR 0127 で1件以上の集約へ揃ったため、かつての意図的な差異は解消している。
  - 窓がブロック単位になり1グループが数千件を抱えうるため、**ヘッダと行データを型で分けてある**（ADR 0038）: `SessionDetailCommandGroupHeader`（`title` / `isRunning` / `shouldRender`・行データを保持しない）を閉状態で使い、`SessionDetailCommandGroupRowWindow.slice(...)` は `if isExpanded` の内側でだけ呼ぶ。展開時の行は末尾 `defaultLimit = 50` 件で、残りは `hiddenRowCount` として「残り N 件を表示」（`expandStep = 50`）で段階展開する。コピー用テキストも押下時にだけ生成する（`ChatMessageDeferredCopyText`。転写のコピーは行ごとのボタンではなく長押し `contextMenu` で提供する → [ADR 0042](../adr/0042-input-bar-send-reveal-and-transcript-long-press-copy.md)）。コピー可否の判定と文字列生成はどちらも `ChatMessageCopyText.commandGroupCopyablePart(for:)` 1本を通す。
- **チャット履歴の末尾ウィンドウ描画**（→ [ADR 0022](../adr/0022-ios-transcript-tail-window.md) / [ADR 0037](../adr/0037-transcript-window-counts-blocks.md)）: 上記の per-message 折りたたみとは別に、チャット履歴全体を**末尾 N ブロックのみ描画**して初回オープンの eager 描画コストを有界化する。**N が数えるのはトップレベルに描画されるブロック数**であって message 数ではない（ADR 0037）——連続するツール実行のまとまりは中に何件入っていても1枠。`TranscriptWindow`（純粋値型・`defaultLimit = 50` / `expandStep = 50`）が totalCount のみから末尾スライスと隠れ件数を返し、`SessionDetailToolCallGrouping.visibleSlice(from:blockLimit:)` が末尾 `blockLimit` ブロックと `hiddenBlockCount` を返す。`SessionDetailTranscriptSlice`（`SessionDetailView` が `@State` で持つ窓から生成）は `visibleMessages` を**可視ブロック列から導く**（id の逆引きはしない＝ id 一意を前提にしない）。超過時のみ先頭に「以前のメッセージを表示（残り k 件）」ボタンを出し、**拡張契機はボタン押下のみ**（+50）。セッション切替で `reset()`。展開時は押下前の先頭可視ブロックをアンカーに保持（`SessionDetailTranscriptExpansionPolicy`・世代ガード付き scrollTo・末尾追従は選ばない）。macOS の非 Lazy VStack + 件数制限（ADR 0030/0051/0127）を単一文脈へ簡約移植したもので、LazyVStack は再導入しない。
- **初回ロード中の接続表示**（→ [ADR 0023](../adr/0023-ios-initial-load-connecting-indicator.md)）: 初回 `load()` が解決するまで `isInitialLoading` を true とし、`isInitialLoading && chatMessages 空 && outputText 空` の間だけ中央に既存 `DSConnectingIndicator` を表示する。終了保証は `load()` の `defer`。新規チャットは別の ViewModel を使うため、このセッション画面のロード表示にドラフト分岐は無い。
- **入力欄の有効条件**（→ [ADR 0028](../adr/0028-input-bar-enabled-on-completed-and-error.md)）: `inputEnabled` が false になるのは `starting` **だけ**。`completed` / `error` で停止したセッションでも入力欄は出したままにする（送信で respawn して復帰できるため）。
- **AskUserQuestion カードの排他**（→ [macOS ADR 0124](../../../macos/docs/adr/0124-user-question-free-text-exclusive.md)・[ADR 0024](../adr/0024-user-question-card-mirror.md)）: 選択状態は View の `@State` 辞書ではなく値型 `UserQuestionFormState`（`selections` / `freeText` / `canSubmit` / `answers` / `seed(from:)`）が持つ。自由入力欄へフォーカスが入ると `freeTextDidFocus(question:)` がその質問の選択肢を解除し、選択肢を触ると自由入力をクリアする（どちらか一方だけが回答になる状態を画面上でも保つ）。自由入力欄は `axis: .vertical` + `lineLimit(1...4)` で右端折り返し。

### 新規チャット（専用画面、stage 5）

下部の「新規チャット」、プロジェクト見出しの「＋」、空の一覧の入口は `Route.newChat(SessionComposeDraft)` を push し、
`Features/NewChat/NewChatView` と `NewChatViewModel` を表示する。以前の placeholder `Session` を `SessionDetailView` に渡す
ドラフト経路は廃止した。新規チャットの状態・モデル選択・プロジェクト選択・初回送信は `SessionDetailViewModel` に含めない。

- `NewChatViewModel.load()` は 3 エージェントのモデル一覧と設定選択肢、`GET /projects`、セッション一覧を並行取得する。
  `GET /projects` 非対応の古い Mac ではセッション一覧からプロジェクトを組み立てる。空の一覧でもプロジェクト未選択で始める。
- 前回のエージェント・モデル・設定・プロジェクトを `NewChatSettingsStore`（Mac と同じ UserDefaults キー群）から復元する。
  モデルは `(kind, modelID)` の組で識別し、表示名を識別子にしない（→ [ADR 0030](../adr/0030-draft-model-selection-kind-and-id.md)）。
  3 エージェントのモデルシートは取得できない欄も残し「取得できません」と表示する。
- 送信はプロジェクト必須を確認してから `POST /sessions`（model・projectId・effort・permission・planMode）→
  `waitUntilReady` → `POST /send` を直列実行する。成功したら実セッションを開く（→ [ADR 0008](../adr/0008-spawn-screen-to-draft-compose.md)）。
  作成失敗は新規チャットに本文を残す。準備待ちまたは初回送信の失敗は作成済みセッションへ移り、本文・添付・赤いエラーを
  `SessionDetailRecovery` で戻す（15 章 U-12）。
- `SessionDetailPresentationState` は View 非依存の表示判定を持つ。状態語、入力欄・停止・使用量、起動表示、PTY 非対応、読み込み・空・取得失敗を値で決める。全状態表は単体テストで確かめる。
- `SessionDetailViewModel` は履歴取得・ポーリング・送信・停止・設定変更を担い、表示判定を `SessionDetailPresentationState` に渡す。PTY はメッセージ・ポーリング・設定取得を行わない。
- `DSSessionNavigationChrome` はセッション詳細の名前・状態とエージェント名・メニューをシステムナビゲーションバーへ載せる。バーの背景と配色は NavigationStack 側の `DSCampNavigationChrome` が設定する。画面ごとの toolbar 背景・色指定は戻る印の appearance を上書きするため重ねない。左上は `NavigationStackHomeBackButton` がシステム戻る印を家へ替え、端スワイプは UIKit の既定動作を保つ。右上メニューは同じ共通部品内で、iOS 26 は丸いガラス面、iOS 18 は背景なしの印だけにする（→ ADR 0048）。
- 削除確認は OS 標準アラートを使い、一覧の `parentSessionId` から子孫件数を数える。名前変更の空欄・同名は送信せず閉じる。
- 発言・返答の `createdAt` は DTO から `ChatMessage` へ渡し、全量・差分の両取得で保持する。長押し見出しは `ChatMessageCopyText.contextMenuTitle(createdAt:timeZone:)` が端末時間帯で `M月d日 HH:mm` に整形する。時刻が無い古い Mac では見出しを付けず、常設の時刻表示はしない（契約 §8.12、ADR 0042）。

## UI 部品（`DesignSystemIOS`）

- `DSMarkdownText`／`DSCodeBlock`／`MarkdownBlockParser`: マークダウン・コードブロック描画（`CodeHighlighter` は「トークン連結＝元コード」を不変条件とする）。swift-markdown-ui 依存。
- `DSAgentBrandIcon`: 共有 DesignSystem の `AgentBrandIcon` でエージェントのロゴを描く（Claude・Codex は単色、Cursor は元の色。再設計の仕様書 2.2）。
- `DSMarkdownText` / `SessionDetailUserMessageBubble`: 返答は左右 16pt の全幅 Markdown。ユーザー発言は右寄せ、`bg.code`・角丸 14・最大幅 78% の吹き出しで描き、添付プレビューは吹き出し内の本文上に 56pt で置く。コピーは**長押し `contextMenu`**（`ChatMessageCopyText.chatMessageCopyContextMenu(copyText:)`）で提供する。
- `DSInputBar`: セッション画面と新規チャットで共有する 2 段の入力欄。本文は 5 行まで伸び、添付は 56pt のサムネイル・`#N`・削除操作・「画像 n/4」を表示する。下段は画像追加、モデル、思考の強さ、権限、任意のプロジェクト、送信／停止。`glassSurface(.inputField)` を使い、iOS 26 はガラス、iOS 18 は素材面と細い線で描く。モデルチップはエージェント名を省き、ロゴ・モデル名・下向き印を出す。幅判定が設定をまとめない場合、チップの文字は本文あり・実行中でも省略しない。文脈ラベル（プロジェクト名で代替する branch 表示）は欄の上に置く（→ [ADR 0012](../adr/0012-input-bar-branch-display-only.md)）。ドラッグで閉じるバーと音声入力は置かない（→ [ADR 0018](../adr/0018-input-bar-remove-drag-and-voice.md)）。
- `DSInputBarLayout`: `Reply` / `Draft` の `cmpVals` と同じ文字幅近似で下段の表示幅を判定する。設定を「…」へまとめ、次に新規チャットのプロジェクト名を印だけにし、最後に下段を折り返す。強い権限は「…」に移さず赤いチップに残す。Dynamic Type のアクセシビリティサイズでは最初から設定をまとめる。
- **セッション設定**: `SessionDetailViewModel.loadModelSettings()` が `GET /sessions/{id}/settings` と `GET /agents/{kind}/models` を読み、Mac 由来の選択肢と既定モデル ID を使う。モデルシートにはそのセッションのエージェントのモデルだけを並べる。モデルは `setModel`、思考の強さ・権限・Plan は `PATCH /sessions/{id}/settings` で選択時に反映し、成功後に settings を取り直す。更新中はチップにスピナーを出す。失敗時は表示値を保ち、入力欄の上に理由を出す。425 は `waitUntilReady` の後に 1 回再送し、409 は失敗として表示する。旧 Mac の 400/404 では設定チップを隠す。Plan は `planMode` で扱い、権限変更で解除する。確認が必要な権限は API 値で判定して確認ダイアログと赤い表示を使う。
- **入力欄の上下の構成**: 入力欄の上は送信・設定変更・添付のエラー → 承認カード → 未回答の質問カード。選択肢が無い単独質問の自由入力はカードから外し、入力欄を「回答を入力」にして送信する。入力欄の下にはガラスを使わない使用量リング行を置く。使用量が無い時は行を出さず、取得失敗時は前の値を古い値として残す。ターンの使用量は最終返答の下に置く（段階 6）。
- `SessionListView`: 大見出し「セッション」の下に、対応待ち（承認・質問・エラー・無応答）・プロジェクト別の一覧・未割当の「その他」を表示する。`SessionListProjection` が API 順の欄と行、同一プロジェクト内の親子木、閉じた欄の状態内訳、行と VoiceOver の表示情報を View 非依存で組み立てる。子の開閉状態は View のメモリにだけ保持する。行は名前と状態語だけを表示し、実行中の名前には Reduce Motion 設定に応じた 1 回の光の帯を重ねる。行表示と一覧読み込み中・空・オフライン・取得エラーは `Features/SessionList/` に置く。
- 追従スクロール `ChatAutoFollowPolicy`: 最下部 80pt 以内にいる時だけ新着へ自動追従（ユーザーが上へスクロール中は追従しない）。
- `DSNavigationChrome.barColorScheme(for:)`: テーマ ID から `ColorScheme` を判定（`phloxLight` → `.light`、それ以外は `.dark` フォールバック）。`DSCampNavigationChromeModifier` が `@AppStorage` でテーマ変更を監視し、`installUIKitAppearanceIfNeeded(for:)` で `UINavigationBarAppearance`/`barStyle` を再適用する。[adr/0004](../adr/0004-ios-appearance-live-switch-via-root-remount.md) の `rootContent.id()` 再マウントとは別経路（`@AppStorage` の `onChange` で駆動）で、SwiftUI 側の `camp*` 色再評価と並行して UIKit グローバル appearance を独立に更新する。再適用は `themeID` が変化した時だけ実行される冪等な経路（`DSNavigationChromeAppearanceInstaller` が直近の `themeID` を保持し、同一テーマの再呼び出しは no-op。適用回数は `appearanceInstallationState` で観測可能。wave-5 → [ADR 0014](../adr/0014-navigation-chrome-appearance-idempotent-install.md)）。

## 共有ストレージとウィジェット拡張 (PhloxWidget)

wave-4 でロック/ホーム画面ウィジェットを追加した（→ [ADR 0009](../adr/0009-widgetkit-app-group-session-status.md)）。

- **ターゲット**: `ios/PhloxWidget/`（`ios/project.yml` の `PhloxWidget`、`type: app-extension`、`APPLICATION_EXTENSION_API_ONLY: YES`）。`PhloxWidgetBundle`（`@main`）が `SessionStatusWidget`（`StaticConfiguration`、`.accessoryRectangular`＋`.systemSmall`）を提供する。本体 `PhloxMobile` ターゲットに `embed: true` で組み込まれる。バンドル ID は本体 `com.phlox.mobile.PhloxMobile`、拡張 `com.phlox.mobile.PhloxMobile.PhloxWidget`。
- **App Group**: `group.com.phlox.mobile`（本体・拡張の両エンタイトルメントに設定）。
- **共有ストア**: `PhloxCore/Shared/SharedSessionStore`（`UserDefaults(suiteName:)` を薄くラップし `SharedSessionSummary`（id/statusLabel/title/detail/updatedAt と optional な displayState）を JSON で read/write。UIKit/WidgetKit 非依存で round-trip 単体テスト可能）。
- **書き込み**: `DesignSystemIOS/SessionGlanceProjection` が `Session.displayState` を最小の `SessionGlanceState` へ変換し、`SharedSessionWriter.write(summaries:)` が入力順を保持して保存＋タイムライン更新する。`AppRoot` は一覧状態の変更時に書く。未取得・失敗では保持し、取得成功の0件は空で上書きする。拡張は `updatedAt` が最新の1件を表示する。`displayState` の無い旧データも読める。
- **描画**: `PhloxWidget/Views/` にホーム・ロックのウィジェットと Live Activity の実 View。`SessionGlanceState` の記号・状態色の数値は `IOSColor` と共通。拡張の依存は `PhloxCore` だけのまま、アプリの外観設定を参照せず端末の `colorScheme` を使う。Dynamic Island の状態色は常にダーク。描画テストのターゲットにも同じ View ソースを含める。
- **タップ**: 既存 scheme に `phlox://session/<id>` を追加し、ウィジェット・Live Activity の `widgetURL` から通知と同じ `pendingSessionID` へ送る。解除・タップ後の一覧取得成功まで保留し、既存の詳細画面（承認・質問カード含む）へ進む。対象が無ければ一覧へ戻して F8。`phlox://pair` と通知の許可時期は維持する。
- **既知の実機ビルドブロッカー**: Apple Developer portal で App ID `com.phlox.mobile.PhloxMobile` と `com.phlox.mobile.PhloxMobile.PhloxWidget` の双方に App Group `group.com.phlox.mobile` を登録しないと、実機向けコード署名が `application-groups` entitlement 不一致で失敗する（ローカルの `project.yml`/entitlements 変更だけでは実機ビルド不可。portal 登録待ちで本 run では未実施）。

## ライブアクティビティ（push 駆動、wave-5）

セッション状態変化（実行中→承認待ち/完了等）を、アプリを閉じていてもロック画面へ自動表示・更新する（→ [ADR 0011](../adr/0011-session-live-activity-push-driven.md)）。

- **iOS**: `PhloxCore/LiveActivity/SessionActivityAttributes`（`ActivityAttributes` 準拠。`ContentState` は `sessionId`/`sessionName`/`status`/`summary`）と `PhloxCore/LiveActivity/LiveActivityCoordinator`（`@available(iOS 17.2, *)` の `actor`）。`PhloxAppDelegate.application(_:didFinishLaunchingWithOptions:)` が iOS 17.2+ かつ UI テスト実行時以外で `LiveActivityCoordinator().start(registrar:bundleId:environment:)` を呼ぶ。`start` は `Activity.pushToStartTokenUpdates`（アプリ全体の push-to-start token）と `activityUpdates`（Activity ごとの update token）を購読し、`ios/App/Push/LiveActivityPushRegistration.swift`（`LiveActivityTokenRegistering` 実装、`POST /device-tokens`）経由で Mac へ登録する。`LiveActivitySessionIndex` が `sessionId → activityId` を1対1に保ち、重複 Activity は即時 `.end(dismissalPolicy: .immediate)` する。
- **Widget 拡張**: `ios/PhloxWidget/SessionLiveActivity.swift`（`ActivityConfiguration<SessionActivityAttributes>`、ロック画面＋Dynamic Island の expanded / compact / minimal）を `PhloxWidgetBundle` に追加登録。
- **macOS 送信経路**: `APNsNotificationBridge`（`AppBootstrap`）の既存 alert 送信（`RemoteSessionNotifier.notify`）に liveactivity 送信を追加。update token 未登録セッションには push-to-start（`event:"start"`）、登録済みなら `update`/`end` を送る。`APNsClient` の `apns-push-type` は呼び出し側からパラメータ化した（従来 alert 固定）。
- **多重起動防止**: macOS 側 `actor LiveActivityStartRegistry`（`APNsNotificationBridge.swift` 内）が `(sessionId, deviceToken)` をキーに `Set` へアトミックに予約してから push-to-start を送信し、送信失敗時は予約を解放する。iOS 側の `LiveActivitySessionIndex` と合わせた2層防御。
- **契約**: iOS `SessionActivityAttributes.ContentState` と macOS の payload エンコーダ（`content-state`/`stale-date`/`dismissal-date`/`attributes-type` 等のキー）を一字一致で固定し、`SessionActivityContractTests`（iOS）で凍結。ワイヤ定義は [macos/docs/specs/apns-companion-contract.md](../../../macos/docs/specs/apns-companion-contract.md) 契約2-LA。
- `DeviceTokenRegistration`/`DeviceTokenStore`（`AgentDomain`）は `tokenType`（`device`/`liveactivity-push-to-start`/`liveactivity-update`）・`activityId`・`sessionId` を追加保持する。
- **未検証**: ロック画面での実表示・APNs 実配信は実機＋実 Mac push が必要なため本 run では未確認（シミュレータのユニット・契約テスト・ビルドまでは green）。

## テスト

`Packages/PhloxKit/Tests` に Swift Testing（`@Test`/`#expect`）＋ XCTest。`actor MockAPI` が `PhloxAPI` を差し替え、outcome/count/script で挙動を注入する。検証設定の正本は `ios/Makefile`（`test` はSwiftPMテスト、`lint` はraw値lint、`generate` と `snapshot`）。旧記述の `.claude/verify.sh` はこのworktreeには無い。App ターゲットは生成後に `xcodebuild build` でビルドする。

### 送信中の本文と添付

送信受付までは入力を残す。成功時は送信前と同じ本文・添付だけをクリアする。途中で編集された入力は成功・失敗ともに保持し、失敗時に古い内容を書き戻さない。
