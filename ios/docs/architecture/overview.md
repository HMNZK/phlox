---
status: active
last-verified: 2026-07-16
---

# アーキテクチャ概要（現行）

> **このファイルの役割**: Phlox-mobile が **今こう動いている** 構成・データフロー・主要 I/F の参照。
> **書かないもの**: なぜその方式か（→ [adr/](../adr/)）・要件（→ [specs/](../specs/)）・作業経緯（→ [docs/delivery/](../../../docs/delivery/)）。

## パッケージ構成

アプリ本体（`App/`）＋ Swift Package `Packages/PhloxKit` ＋ WidgetKit 拡張ターゲット `PhloxWidget/`（`ios/project.yml` の `PhloxWidget` app-extension ターゲット、`PhloxCore` のみに依存。→ [共有ストレージとウィジェット拡張](#共有ストレージとウィジェット拡張-phloxwidget)）。PhloxKit は次のモジュールに層分けされる。

| モジュール | 役割 |
|---|---|
| `PhloxCore` | ドメイン型（`Session`・`ChatMessage`・`SubAgentSummary`・`TurnUsage`・`MessagesDelta`・`SendRequest`/`SendAttachment`・`AgentModels`/`SessionModelOption`・`CLIUsage`/`UsageBucket`/`CLIUsageState`・`PhloxError` 等）と `PhloxAPI` プロトコル。UI・ネットワークに非依存。`Shared/` サブディレクトリに `SharedSessionStore`/`SharedSessionWriter`（App Group 経由でウィジェット拡張と状態共有、→ [共有ストレージとウィジェット拡張](#共有ストレージとウィジェット拡張-phloxwidget)） |
| `PhloxNetworking` | `PhloxAPIClient`（`PhloxAPI` の HTTP 実装）・`HostTrustPolicy`・DTO ↔ ドメイン変換 |
| `DesignSystemIOS` | 再利用 UI 部品（チャットバブル・マークダウン・アバター・トークン） |
| `Features` | 画面ごとの `@Observable` ViewModel と SwiftUI View |

### `Features` サブモジュール

| サブモジュール | 現行構成 |
|---|---|
| `Features/ConnectionSettings` | 接続設定画面。QR 適用済みの接続先を読み取り専用で表示し、接続／再接続は「QRで接続」から行う。保存済み接続先への疎通テストを持つ。到達性は `ReachabilityMonitor`（`NWPathMonitor`＋`/sessions` healthCheck）が保持し、QR ペアリング完了・手動「再接続を試す」で `refresh()` により経路イベントを待たず即再判定する（→ [ADR 0019](../adr/0019-reachability-on-demand-refresh.md)）。QR ペアリング直後は全画面「接続中…」オーバーレイ（`AppModel.isConnecting`／`AppRoot.ConnectingOverlayView`）を出し、その閉じ判定を到達性ではなく**セッション一覧の取得成功**（`PairingConnectGate`＋`SessionListViewModel.state`）でゲートしてオフライン画面の一瞬のちらつきを隠す。オーバーレイ本体はリッチな中央アニメーション `DSConnectingIndicator`（`Canvas`＋`TimelineView(.animation)` のレーダー状リング＋回転円弧＋脈動スパーク・Reduce Motion 時は静的）で、タイムアウト時は閉じずに原因（`AppModel.connectFailure`＝一覧エラー優先／無ければオフライン画面と同一コピー）と再試行/閉じるを同じ画面に表示する（→ [ADR 0021](../adr/0021-connecting-overlay-gated-on-session-list-load.md)） |
| `Features/Pairing` | `QRScanScreen`、`PairingApplyViewModel`、`QRImageDecoder`。QR から読み取った host・port・token を検証して接続設定へ一括適用する |
| `Features/Settings` | `@Observable` の `AppSettings` と `AppSettingsStoring`。`UserDefaults` 永続化の Face ID（**既定オフ** → [ADR 0017](../adr/0017-face-id-launch-gate-default-off.md)）、通知（既定オン）、外観（`AppearancePreference.system/light/dark`）と About を提供する |
| `Features/SessionList` | セッション一覧画面（タイトル「Projects」、wave-4 で刷新 → [ADR 0008](../adr/0008-spawn-screen-to-draft-compose.md)）。件数/ホストの subtitle・上部空白・右下 FAB は撤去（`providesListSubtitle`/`providesSpawnFAB` = false）。`SessionGrouping.grouped(from:)` が `projectId ?? projectName` をキーにセッションを `ProjectGroup` へ束ね、`SessionListView` は `DisclosureGroup`（既定全展開）で表示する。各プロジェクトグループ末尾（グループが空の場合は単独行）に「+ セッションを追加」行（`providesPerProjectAddSessionRow` = true）を出し、タップで `onAddSession(project:)` → `Route.sessionComposeDraft(project:)` へ遷移する |
| `Features/Spawn` | wave-4 で廃止（ソースファイル削除、ディレクトリのみ残置）。新規セッション作成はセッション一覧の「+ セッションを追加」→ドラフト compose フローに統合された（→ [ADR 0008](../adr/0008-spawn-screen-to-draft-compose.md)） |
| `Features/SessionsOverview` | 複数セッションの俯瞰（`OverviewMode` grid/single 切替）。ソース（`SessionsOverviewView`/`SessionsOverviewViewModel`）は残置しているが、wave-4 で下部タブから `.overview` が削除されたため **UI から到達不能**（デッドコード。→ [ADR 0007](../adr/0007-remove-overview-tab.md)） |
| `Features/Usage` | アカウント単位の CLI 使用量表示。`UsageViewModel.load()` が `cliUsage()` を叩き、`state: .unavailable` のエージェントはバッジのみ表示 |
| `Features/AppShell` | 下部固定タブバーの状態機械。`AppTab`（`.sessions/.settings/.usage` の3種、wave-4 で `.overview` を削除 → [ADR 0007](../adr/0007-remove-overview-tab.md)）と `AppShellViewModel.selectTab(_:)`（現在は単純な選択更新のみ。旧・俯瞰タブ再選択トグルは削除済み） |

## アプリルートの設定反映

### 外観のライブ反映

`AppRoot` は `AppSettings.appearance` を監視し、`rootContent` に `.preferredColorScheme` を適用する。同時に `phlox.theme` を `AppearancePreference.themeID` へ同期し、`.id(activeThemeID)` で `rootContent` を再描画する。`system` 選択時は `@Environment(\.colorScheme)` に追従してライト／ダークのテーマ ID を切り替える。

### Face ID 状態機械

`AppModel.initialAuthState` が起動時の認証状態を決め、`shouldRelock` が背景復帰時の再ロック要否を管理する。`AppRoot` は `scenePhase` が `.background` へ遷移した時に再ロックし、Face ID 設定を無効にした時はロック状態を解除する。**Face ID 設定の既定はオフ**（`UserDefaultsAppSettingsStore.faceIDEnabled` の未設定フォールバックは `false`＝新規インストール時は起動ロックしない。設定で ON にしたときだけ起動ロック・背景復帰時の再ロックが働く。`initialAuthState`/`shouldRelock` は `faceIDEnabled` を明示引数で受けるため既定値変更の影響を受けない → [ADR 0017](../adr/0017-face-id-launch-gate-default-off.md)）。

## アプリシェル（下部固定タブバー、`Features/AppShell`）

`AppRoot`（`ios/App/AppRoot.swift`）は SwiftUI 標準の `TabView` を使わず、`VStack`（コンテンツ＋`Divider`＋タブ行）
の**独自タブバー**を組む（`appTabBar(appShell:)`）。タブ行は `AppTab.allCases`（宣言順 `.sessions → .settings →
.usage` の3タブ、wave-4 で `.overview` を廃止 → [ADR 0007](../adr/0007-remove-overview-tab.md)）をアイコン＋下ラベルの
`Button` として並べ、各 `Button` の action は `AppShellViewModel.handleTabTap(tab)` を直接呼ぶ（独自 `Button` 採用理由は
[ADR 0006](../adr/0006-appshell-custom-tab-bar.md)）。

`AppShellViewModel.selectTab(_:)` は単純に `selectedTab` を更新するのみ（旧・俯瞰タブ再選択での grid⇔single
反転ロジックは `.overview` 廃止に伴い削除済み）。`handleTabTap` は `selectTab` への薄いラッパー。

## ネットワーク層（`PhloxNetworking`）

`PhloxAPIClient` が `PhloxAPI` プロトコルを実装する。エンドポイントは Mac 側 Phlox サーバーの REST。動的パスセグメント（sessionID・subAgentID・approvalID）は `percentEncodedPathSegment` で個別にエンコードしてから `components.percentEncodedPath` へ組み立てる（二重エンコードと不正文字での `percentEncodedPath` setter クラッシュを回避）。

主要エンドポイント（`sessions/{id}` 基点。API 拡張分は契約 v1 — [../specs/mobile-api-extensions-contract.md](../specs/mobile-api-extensions-contract.md)）:

| メソッド | HTTP | パス |
|---|---|---|
| `listSessions` / `spawn` | GET / POST | `sessions` |
| `send`（text＋images） | POST | `sessions/{id}/messages` |
| `messages` | GET | `sessions/{id}/messages` |
| `messagesDelta` | GET | `sessions/{id}/messages?since=<cursor>&wait=<ms>` |
| `interrupt` | POST | `sessions/{id}/interrupt` |
| `subAgents` | GET | `sessions/{id}/subagents` |
| `subAgentMessages` | GET | `sessions/{id}/subagents/{subAgentID}/messages` |
| `usage` | GET | `sessions/{id}/usage` |
| `output` / `waitUntilReady` / `remove` | GET / GET / DELETE | `sessions/{id}/output` `.../ready` `sessions/{id}` |
| `approvals` / `respond` | GET / POST | `approvals` `approvals/{id}` |
| `sessionSettings` / `setModel` | GET / POST | `sessions/{id}/settings` `sessions/{id}/model`（契約 §6・モデル選択） |
| `agentModels(kind:)` | GET | `agents/{kind}/models`（契約 §7.3・spawn 前モデル一覧） |
| `cliUsage()` | GET | `usage`（契約 §7.4・アカウント単位使用量） |

**前方互換**: `messages` 系はメッセージ DTO の未知 `type` を `toDomain` が `nil` にし `compactMap` で除外する。`subAgents` の未知ステータスは `unknown` へ写像（サーバーが `failed` を送っても壊れない）。差分ポーリングで 404/501 を受けたら `messages()` 全量取得へフォールバックする（旧サーバー互換）。

**信頼ポリシー**: `HostTrustPolicy` が `*.ts.net`（Tailscale MagicDNS、ラベル境界を検証）とプライベート IP レンジ（IPv4 は4オクテット厳密パース＋CIDR ビット境界）にのみ `Authorization` ヘッダを付与する。平文 HTTP でのトークン露出を信頼済みネットワークに限定する（→ [doc/adr/0003-plaintext-http-tailscale-client-guard.md](../adr/0003-plaintext-http-tailscale-client-guard.md)）。

## セッション詳細のデータフロー（`Features/SessionDetail`）

`SessionDetailViewModel`（`@MainActor @Observable`）がチャット面の状態を持つ。

- **画面構成**（wave-6）: 承認リクエスト（`approvalSection`）＋ターミナル出力（`transcriptSection`）＋入力バー（`inputBarSection`）で構成される。wave-5 まで存在したヘッダーカード（エージェントバッジ・ステータスチップ・「エージェント名 + 開始時刻」のメタ行を1枚のカードにまとめた表示）は撤去され、代替表示は無い。
- **メッセージ取得**: 起動時 `messages()`、以降は `messagesDelta(since:cursor)` でカーソル前進しながら差分採用（`adoptMessagesFromDelta`＝スナップショットなら置換・差分なら追記、cursor 更新）。一時失敗では表示を消さない。
- **送信**: `SendRequest`（text＋`[SendAttachment]`）。送信完了バナー（旧 `SendState.sent`）は廃止。
- **停止**: `canInterrupt` が真のとき `stop()` が `interrupt` を呼ぶ。409（既に停止/完了）はボタン無効化で吸収。
- **usage**: セッションが running→idle へ遷移した時に `usage()` を取得し `turnUsage`（コスト・コンテキスト使用量）を表示。
- **サブエージェント解決**: `resolveSubAgentID(forMessageID:)` が `subAgents` の `markerMessageID` から行タップ対象の subAgentID を引く。
- **モデル選択**: `sessionSettings()` が `availableModels` を返した時だけモデルチップ（選択中モデルの表示名）を出し、タップでモデル選択シート（`ModelPickerSheet`）を開いて `setModel` を呼ぶ。非対応セッション（codex 等）・取得失敗時はチップ非表示に劣化（画面全体は壊さない）。チップは **入力欄内（`DSInputBar` の `modelSelector` スロット）と右上メニューの2箇所**から到達できる（wave-4 で入力欄チップを復活 → [ADR 0010](../adr/0010-restore-inline-model-selector-chip.md)）。
- **添付**: `addAttachments()` が最大4枚・各4MiB・合計8MiB を検証（超過はバッチ全体を拒否）、`normalizeAttachment` が magic-byte で実体判定し HEIC を JPEG 再エンコードして mediaType とバイトを一致させる。プレビューは一度だけ downsample して `previewData` にキャッシュ。送信した添付は、送信テキストで送信後スナップショットのユーザーメッセージへ突き合わせ（`SessionAttachmentReconciler`）、message.id 起点の side-map（`attachmentCountsByMessageID`）に保持してチャット吹き出しにバッジ表示する（サーバ/ワイヤ不変・クライアント完結 → [ADR 0020](../adr/0020-chat-attachment-badge-client-side.md)）。
- **右上メニューの presentation**（wave-5）: モデル変更シート・rename アラートは `SessionDetailViewModel` の `private enum MenuPresentation { case modelPicker, rename }` を単一ソースとして排他管理する（`isModelSheetPresented`/`isRenamePresented` はこの enum への computed property）。`.sheet` は `.alert` とは別の View 階層（チャットスクロール＋`inputBarSection` を含む内側 VStack）に付与され、同一 View への複数 presentation 併置を避ける（→ [ADR 0013](../adr/0013-session-detail-menu-presentation-single-source.md)）。
- **メッセージ表示の折りたたみ**（wave-5）: reasoning／command／fileChange 行はデフォルト折りたたみ（ヘッダ＋先頭48文字プレビューのみ表示）。タップで展開/再折りたたみし、展開状態は `expandedMessageIDs`（`ChatMessage.id` キーの `Set`）で message 単位に保持され、3秒ポーリングでの再取得後も失われない。user/agent の通常メッセージ・error・subAgent 行は対象外。

### ドラフト compose（未 spawn セッションの詳細画面、wave-4）

セッション一覧の「+ セッションを追加」は `Route.sessionComposeDraft(project:)` へ遷移し、`DraftSessionComposeDestination`
が placeholder `Session`（id `"draft-compose"`）を `SessionDetailView` に渡し `Environment(\.sessionComposeDraft)` を
セットする。実セッションが存在しないため:

- `SessionDetailViewModel.isAwaitingInitialSpawn`（`draftProject != nil && !hasSpawnedDraft`）の間は
  `startPolling(composeDraft:)` が実 polling を起動せず、`prepareDraft(_:)` が `claudeCode`/`cursor`/`codex` 3種の
  `agentModels(kind:)` カタログだけを取得してモデルピッカーを準備する（codex はカタログ常時空のため agent-only の
  1行を必ず追加）。
- 初回送信（`sendMessage(composeDraft:)`）で **`spawn(kind, model) → waitUntilReady → send` を1回の操作内で順序実行**する。
  `spawn` の応答 `Session` は `listSessions` の反映を待たず `session = spawned` として直渡しで採用し、一覧非同期反映との
  レースを避ける（→ [ADR 0008](../adr/0008-spawn-screen-to-draft-compose.md)）。

`SubAgentDetailViewModel` は解決済み subAgentID の会話を `subAgentMessages` で取得し、本体と同じチャット描画で表示・3秒ポーリング（画面離脱の `.task` キャンセルで停止）。

## UI 部品（`DesignSystemIOS`）

- `DSMarkdownText`／`DSCodeBlock`／`MarkdownBlockParser`: マークダウン・コードブロック描画（`CodeHighlighter` は「トークン連結＝元コード」を不変条件とする）。swift-markdown-ui 依存。
- `DSAgentAvatar`: 共有 DesignSystem の `AgentBrandIcon`（SVG）でエージェントアバターを描画。
- `DSChatBubble`: チャットバブル。macOS 版と同配色（user = `DSColor.userBubble` の淡面＋`textPrimary` 前景 / agent = 背景なし）。agent バブル本文は `DSMarkdownText` で描画。コピーは**長押し `contextMenu`**（`ChatMessageCopyText.chatMessageCopyContextMenu(copyText:)`）で提供し、wave-4 で常時表示のコピーボタンを撤去した（`providesLongPressCopy` = true / `providesAlwaysVisibleCopyButton` = false）。wave-8 で user バブルに画像添付バッジ（`attachmentImageCount`＝非 nil のとき `Image("photo")`＋`attachmentBadgeText(count:)`＝「画像」/「画像 ×N」）を追加し、wave-9 でバッジをバブル内から**バブルの外（下・右寄せのカプセル型チップ）へ分離**した（macOS デスクトップと同じ「別要素」配置。テキスト空で画像のみのときは空バブルを出さずバッジのみ → [ADR 0020](../adr/0020-chat-attachment-badge-client-side.md)）。
- `DSInputBar`: 送信・写真添付付きの**コンパクトなピル型**入力バー（wave-6 で角丸カードから `Capsule()` へ再デザイン、`providesCardChrome = false` / `providesPillChrome = true` → [ADR 0016](../adr/0016-input-bar-compact-pill-redesign.md)）。写真添付ボタン・テキストフィールド・モデルセレクタスロット・送信/停止アクションボタンを `pillRow` という1つの `HStack` に横並びする（wave-7 で上部のドラッグ閉じバー `dragDismissAffordance` とマイクボタンを撤去した → [ADR 0018](../adr/0018-input-bar-remove-drag-and-voice.md)。`providesDragToDismiss` = false / `providesVoiceInput` = false。キーボードを閉じる操作はチャット面の `.scrollDismissesKeyboard(.interactively)` に委譲）。**送信/停止は右端の同一スロットに常設**（`DSInputBarActionState`: `.send(isEnabled:)`/`.stop`。`isRunning` が真なら `.stop`、それ以外は常に `.send(isEnabled: canSubmit)`＝空文字・送信不能時も無効・淡色 `opacity(0.45)` の送信ボタンを据える。wave-6 の `.none`＝空文字時非表示は wave-7 で廃止した → [ADR 0018](../adr/0018-input-bar-remove-drag-and-voice.md)）で排他表示し、`SessionDetailView` 側の別置き停止ボタンは廃止した。フォーカス時の枠色変化は無く、常に `DSColor.campCardBorder` の中立色固定（`usesNeutralFocusBorder` = true / `usesAccentFocusBorder` = false）。`modelSelector: () -> some View` の `@ViewBuilder` スロット（既定 `EmptyView()`、`providesInlineModelSelectorSlot` = true、安静時は空スロットでピルに影響しない）と `contextLabel: String?`（branch 風表示。`Session` に branch フィールドは無くプロジェクト名で代替、→ [ADR 0012](../adr/0012-input-bar-branch-display-only.md)）を持ち、呼び出し元（`SessionDetailView`）がモデルセレクタチップと表示名を差し込む（→ [ADR 0010](../adr/0010-restore-inline-model-selector-chip.md)）。**音声入力ボタンは wave-7 で入力欄から撤去された**（→ [ADR 0018](../adr/0018-input-bar-remove-drag-and-voice.md)）。撤去に伴い `DSVoiceInputController` は入力欄（`DSInputBar`）から参照されなくなり孤児化したが、クラス本体と `Info.plist`/`project.yml` の mic/speech 権限文言は撤去せず温存している（後続判断事項）。以下は温存された同コントローラの構成の記録: `DSVoiceInputController`（`@MainActor @Observable`、状態は `idle/requestingPermission/listening/denied/unavailable/failed`）を介した音声入力で、認識結果を `inputText` へ反映する。音声認識本体は `VoiceInputRecognizing` プロトコル（`authorizationStatus()`/`requestAuthorization()`/`startRecognition(onTranscription:onFinish:onError:)`/`stopRecognition()`）越しに抽象化され、既定実装は Speech/AVFoundation ベースの `DSLiveVoiceInputRecognizer`（ユニットテストは protocol をモック差し替え、実 OS API は対象外）。`startRecognition` は危険 API（`AVAudioSession.setActive`/`installTap`/`AVAudioEngine.start`）を呼ぶ前に、二重起動でないこと（`DSVoiceRecognitionSetupState`）・simulator でないこと・入力フォーマットが妥当なこと（`DSVoiceAudioFormatValidator`、活性化後の `inputFormat(forBus: 0)` を検証）を確認し、TCC 権限コールバック（`SFSpeechRecognizer.requestAuthorization`/`AVAudioApplication.requestRecordPermission`）は `nonisolated static` 関数越しに呼ぶ（wave-6、根拠は → [ADR 0015](../adr/0015-voice-input-crash-hardening.md)）。wave-4 でキーボード上の「完了」ツールバーを撤去し（`providesKeyboardDismissToolbar` = false）、キーボードを閉じる操作はチャット面の `.scrollDismissesKeyboard(.interactively)` に委譲した（送信ボタンとの重なり解消）。
- `DSSessionRow`: セッション一覧行。エージェントバッジは `DSAgentAvatar`（ブランド SVG）で描画。
- 追従スクロール `ChatAutoFollowPolicy`: 最下部 80pt 以内にいる時だけ新着へ自動追従（ユーザーが上へスクロール中は追従しない）。
- `DSNavigationChrome.barColorScheme(for:)`: テーマ ID から `ColorScheme` を判定（`phloxLight` → `.light`、それ以外は `.dark` フォールバック）。`DSCampNavigationChromeModifier` が `@AppStorage` でテーマ変更を監視し、`installUIKitAppearanceIfNeeded(for:)` で `UINavigationBarAppearance`/`barStyle` を再適用する。[adr/0004](../adr/0004-ios-appearance-live-switch-via-root-remount.md) の `rootContent.id()` 再マウントとは別経路（`@AppStorage` の `onChange` で駆動）で、SwiftUI 側の `camp*` 色再評価と並行して UIKit グローバル appearance を独立に更新する。再適用は `themeID` が変化した時だけ実行される冪等な経路（`DSNavigationChromeAppearanceInstaller` が直近の `themeID` を保持し、同一テーマの再呼び出しは no-op。適用回数は `appearanceInstallationState` で観測可能。wave-5 → [ADR 0014](../adr/0014-navigation-chrome-appearance-idempotent-install.md)）。

## 共有ストレージとウィジェット拡張 (PhloxWidget)

wave-4 でロック/ホーム画面ウィジェットを追加した（→ [ADR 0009](../adr/0009-widgetkit-app-group-session-status.md)）。

- **ターゲット**: `ios/PhloxWidget/`（`ios/project.yml` の `PhloxWidget`、`type: app-extension`、`APPLICATION_EXTENSION_API_ONLY: YES`）。`PhloxWidgetBundle`（`@main`）が `SessionStatusWidget`（`StaticConfiguration`、`.accessoryRectangular`＋`.systemSmall`）を提供する。本体 `PhloxMobile` ターゲットに `embed: true` で組み込まれる。バンドル ID は本体 `com.phlox.mobile.PhloxMobile`、拡張 `com.phlox.mobile.PhloxMobile.PhloxWidget`。
- **App Group**: `group.com.phlox.mobile`（本体・拡張の両エンタイトルメントに設定）。
- **共有ストア**: `PhloxCore/Shared/SharedSessionStore`（`UserDefaults(suiteName:)` を薄くラップし `SharedSessionSummary`（id/statusLabel/title/detail/updatedAt）を JSON で read/write。UIKit/WidgetKit 非依存で round-trip 単体テスト可能）。
- **書き込み**: `PhloxCore/Shared/SharedSessionWriter` が `[Session]` → `[SharedSessionSummary]` 変換（`updatedAt` 降順）＋ `SharedSessionStore.write` ＋ `WidgetCenter.shared.reloadTimelines(ofKind:)` を担う。`AppRoot`（`sharedSessionWriter` プロパティ）が起動時 `.task` と `listVM.lastKnownSessions` の `onChange` の両方で `writeSharedSessionState(_:)` を呼ぶ。**未ロード・一時的な空配列での上書きは `guard !sessions.isEmpty else { return }` で抑止**し、直近の非空状態を保持する（起動直後の空上書きでウィジェットが「NO SESSIONS」に潰れるバグの修正、→ ADR 0009）。
- **既知の実機ビルドブロッカー**: Apple Developer portal で App ID `com.phlox.mobile.PhloxMobile` と `com.phlox.mobile.PhloxMobile.PhloxWidget` の双方に App Group `group.com.phlox.mobile` を登録しないと、実機向けコード署名が `application-groups` entitlement 不一致で失敗する（ローカルの `project.yml`/entitlements 変更だけでは実機ビルド不可。portal 登録待ちで本 run では未実施）。

## ライブアクティビティ（push 駆動、wave-5）

セッション状態変化（実行中→承認待ち/完了等）を、アプリを閉じていてもロック画面へ自動表示・更新する（→ [ADR 0011](../adr/0011-session-live-activity-push-driven.md)）。

- **iOS**: `PhloxCore/LiveActivity/SessionActivityAttributes`（`ActivityAttributes` 準拠。`ContentState` は `sessionId`/`sessionName`/`status`/`summary`）と `PhloxCore/LiveActivity/LiveActivityCoordinator`（`@available(iOS 17.2, *)` の `actor`）。`PhloxAppDelegate.application(_:didFinishLaunchingWithOptions:)` が iOS 17.2+ かつ UI テスト実行時以外で `LiveActivityCoordinator().start(registrar:bundleId:environment:)` を呼ぶ。`start` は `Activity.pushToStartTokenUpdates`（アプリ全体の push-to-start token）と `activityUpdates`（Activity ごとの update token）を購読し、`ios/App/Push/LiveActivityPushRegistration.swift`（`LiveActivityTokenRegistering` 実装、`POST /device-tokens`）経由で Mac へ登録する。`LiveActivitySessionIndex` が `sessionId → activityId` を1対1に保ち、重複 Activity は即時 `.end(dismissalPolicy: .immediate)` する。
- **Widget 拡張**: `ios/PhloxWidget/SessionLiveActivity.swift`（`ActivityConfiguration<SessionActivityAttributes>`、ロック画面＋Dynamic Island 最小構成）を `PhloxWidgetBundle` に追加登録。
- **macOS 送信経路**: `APNsNotificationBridge`（`AppBootstrap`）の既存 alert 送信（`RemoteSessionNotifier.notify`）に liveactivity 送信を追加。update token 未登録セッションには push-to-start（`event:"start"`）、登録済みなら `update`/`end` を送る。`APNsClient` の `apns-push-type` は呼び出し側からパラメータ化した（従来 alert 固定）。
- **多重起動防止**: macOS 側 `actor LiveActivityStartRegistry`（`APNsNotificationBridge.swift` 内）が `(sessionId, deviceToken)` をキーに `Set` へアトミックに予約してから push-to-start を送信し、送信失敗時は予約を解放する。iOS 側の `LiveActivitySessionIndex` と合わせた2層防御。
- **契約**: iOS `SessionActivityAttributes.ContentState` と macOS の payload エンコーダ（`content-state`/`stale-date`/`dismissal-date`/`attributes-type` 等のキー）を一字一致で固定し、`SessionActivityContractTests`（iOS）で凍結。ワイヤ定義は [macos/docs/specs/apns-companion-contract.md](../../../macos/docs/specs/apns-companion-contract.md) 契約2-LA。
- `DeviceTokenRegistration`/`DeviceTokenStore`（`AgentDomain`）は `tokenType`（`device`/`liveactivity-push-to-start`/`liveactivity-update`）・`activityId`・`sessionId` を追加保持する。
- **未検証**: ロック画面での実表示・APNs 実配信は実機＋実 Mac push が必要なため本 run では未確認（シミュレータのユニット・契約テスト・ビルドまでは green）。

## テスト

`Packages/PhloxKit/Tests` に Swift Testing（`@Test`/`#expect`）＋ XCTest。`actor MockAPI` が `PhloxAPI` を差し替え、outcome/count/script で挙動を注入する。検証ゲートは `.claude/verify.sh`（`swift test` 全数＋raw 値 lint）。App ターゲットは `make generate && make build`。
