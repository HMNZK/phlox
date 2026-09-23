---
status: active
last-verified: 2026-09-24
---

# 0037: UI 再構築（design_handoff_phlox_ui）worklog

> **このファイルの役割**: `design_handoff_phlox_ui/` の再設計を画面ごとに実装した記録。各段（P1〜P12）の「機能一覧の該当行 → 実装箇所」の対応表、決定、未確定事項の扱い、検証結果を残す。要件は `macos/docs/specs/ui-feature-inventory.md`（以下「機能一覧」）。

## 未確定事項の扱い（全段共通）

README「未確定事項」に当たるものは、現行の挙動を既定にして画面には出さない（2026-09-23 ユーザー承認）。確定済みとして扱うもの:

- ⌘W / ⌘1–9 は 13 Review の確定版キー一覧どおり（2026-09-23 ユーザー確認）。
- 設定は 6 タブ（README「読む順番」10 の記述）。

## P1 デザインシステム（12 Design System）

### 対応表

| 機能一覧 | 内容 | 実装箇所 |
|---|---|---|
| 20章 トークン（色） | 背景 8 面・文字 3 段・accent/accentFill/accentInk・選択・差分・端末 | `DesignSystem/DesignPalette.swift`（`DesignPalette.phloxLight` / `.phloxDark` が確定値、`derived` が他 8 テーマの導出）、`Tokens.swift` の `DSColor.windowBackground` ほか |
| 20章 トークン（状態色） | 対応待ち 4 状態の記号・文字・面、無応答（紫）の追加 | `AttentionColors`、`DSColor.attentionMark/Ink/Tint(_:)`、`DSColor.statusStalled` |
| 20章 トークン（文字） | 24/17/14/13/12.5/12/11.5/11 | `DSFont.emptyTitle` `sheetTitle` `sessionTitle` `row` `dense` `auxiliary` `stateLabel` `meta` |
| 20章 トークン（余白・角丸・高さ・影） | 6pt 余白、角丸 6/10、ツールバー 52・タブ列 32・行 28・カード見出し 32・分割線の当たり 8、サイドバー 260（220–360）・インスペクタ 280（260–340）、影 3 種 | `DSSpacing.chip`、`DSRadius.row` `.attention`、`DSLayout.*`、`DSShadow.gridTile` `.popover` `.window` |
| 20章 エージェントの頭文字の面 | Claude/Codex/Cursor の oklch 値、カスタムは agents.json の色を 30% | `DSColor.agentInitialFill(for:)` |
| 17章 状態の描き分け | 起動中・待機・実行中・承認待ち・質問待ち・完了（未読/既読）・エラー・無応答。色は対応待ちだけ | `StatusBadge.swift` の `SessionDisplayState`（`resolve` / `label` / `color` / `attentionKind`）、`AttentionKind` |
| 20章 StatusDot | 廃止（点滅もやめる） | 削除。サイドバー行・グリッドのタイル見出しは `StatusLabel` の文言だけにした（`DashboardSidebarView.swift` / `PaneLayoutView.swift`） |
| 20章 AgentKindBadge | 廃止 | 削除（呼び出し元なし） |
| 20章 CapsuleBadge / StatusCapsuleBadge | 採用。ドットと SF Symbol を使わず文字と面だけ | `CapsuleBadge(label:ink:tint:)`、`StatusCapsuleBadge(state:elapsed:)` |
| 20章 RunningCountBadge | 採用。「n 実行中」に日本語化、無彩色 | `RunningCountBadge.label(count:nested:japanese:)` |
| 20章 StatusLabel | 継続。対応待ちだけ太字＋状態色 | `StatusLabel(status:hasUnseenCompletion:isStalled:)`。VoiceOver は「状態 — 次の操作」 |
| 21章 用語 | 「入力待ち」「停止」「回答待ち」をやめ「待機」「完了」「質問待ち」 | `StatusBadge.label(for:)`、次の操作の文言「選択して許可するか決める」 |

### 決定・食い違い

- **Phlox Light の承認待ちの記号 #E39A2D は白地で 2.35:1**。12 の「記号 3:1」を満たさない。確定値のまま使い、文言（#8A5300、6.3:1）で状態を伝える。`DesignPaletteTests.markExceptions` に明記。デザイン側の確認事項として報告。
- **弱い文字（#75757B / #8E8E94）はサイドバーの旧注意面（未読行の塗り、`DSColor.idleHighlight`）で 4.56:1 を割る**ため、`AppTheme.designText` が本文色へ寄せている（実効値はライト約 #5F5F65、ダーク約 #A8A8AC）。新デザインでは未読行を塗らないので、P4 で旧注意面をやめた時点で補正の対象面から外し、確定値に戻す。
- UI の accent（`DSColor.accent`）はダークで #E08865。ブランドのコーラル #D97757 は `AppTheme.accent` と `DSColor.chatAccent` に残す（ターミナル・テーマ見本・チャットのインラインコード）。
- 差分の色を青/赤から緑/赤へ変えた（`DSColor.diffAdded/diffRemoved` を palette へ接続）。
- 無応答の判定（120 秒）はまだ無い。`SessionDisplayState.resolve(isStalled:)` の入口だけ作り、判定の配線は P5（会話）で入れる。
- 旧トークン `statusRunning` / `statusCompleted` 等は、呼び出し元の画面を作り直す段（P4・P7 ほか）で使わなくなるまで残す。

### テストの更新（意図した値の追従のみ）

`AcceptanceSessionStatusWordsTests` / `StatusBadgeTests` / `StatusLocalizedLabelTests`（語彙）、`TokensTests`（影・accent）、`AppThemeTests`（無彩色の許容差を Phlox / Phlox Light だけに限定）、`AcceptanceSidebarTextContrastTests` と `AcceptanceThemePreviewModelTests`（Phlox / Phlox Light の固定値）、`ChatToolCallTokenTests`（#F2F2F4 の青み 2/255）。`RunningBlinkDotTests` は `StatusDot` 削除に伴い削除。新設: `DesignPaletteTests`（確定値・10 テーマのコントラスト・`SessionDisplayState`）。

## P1' チームビュー・Agora 討論・討論設定の削除（機能一覧 6章・12.5節）

### 対応表

| 機能一覧 | 扱い | 実装箇所 |
|---|---|---|
| 6章 チームビュー（タイムライン・チームコンポーザ・行の描き分け） | 削除 | `TeamTimeline*` `TeamComposer*` `TeamViewBranding` `AgentChatTimeline` `AgentChatRowPolicy` を削除。`ViewMode.team` を削除し、表示モードは単体／グリッドの 2 つ（`AppRouter.toggleViewMode`、`DashboardTopBarControls.ViewModeToggle`、`DashboardDetailView`、`SidebarVisibilityPolicy`） |
| 6章 Agora 討論（エンジン・コーディネータ・参加者・発言抽出・ヘッダ） | 削除 | `Agora*.swift` と `ComposerDestinationLabel+Agora.swift` を削除。`DashboardViewModel` の討論状態・開始/停止/発言/参加者追加/ポーリング、`ControlActionDashboard.agoraParticipantLanded` を削除。`ComposerDestinationLabel.Destination` の `startDiscussion` / `discussionUtterance` を削除 |
| 12.5節 討論設定（`phlox.agora.*` 4 項目） | 削除 | `App/SettingsView.swift` の詳細タブから削除。保存済みの UserDefaults 値は読まなくなるだけで消さない |
| 21章 文言「討論」 | 削除 | `Localizable.xcstrings` のキー「討論」（コードから参照なし） |

### 残したもの（画面の機能ではないため）

- Control API `POST /sessions` の `role` と `scripts/phlox spawn --role`、`PersistedSessionDescriptor.role` の保存。外部契約（phlox-cli スキルが記載）であり、`role` 付き claudeCode spawn をチャットで起動する挙動もそのまま。この強制は討論のリレーのための仕様だったので、討論が無くなった今は理由を失っている（CLI に backend 指定が無く、`--role` 付きでは端末起動を選べない）。変えるかは別途判断（報告済み）。
- `TerminalUI` の `AcceptanceTeamViewLogicalLinesTests`（名前にチームが残るが、検査対象は端末の論理行でチームビューに依存しない）。

### テスト

チーム・討論専用のテスト 32 ファイルを削除。`AgoraRoleWhiteboxTests` は中身が role 保存（残す機能）の検査だったため `RolePersistenceWhiteboxTests` に改名して残した。設定の表示分類 `SettingsGroup` から Section ID `discussion` を外した（`AcceptanceSettingsGroupingModelTests` は 13 ID に更新）。`.team` を使っていた `AppRouterSelectionTests` `AcceptanceCodexChatParityRouteTests` `TrailingTopBarLayoutWhiteboxTests` `SidebarVisibilityPolicyWhiteboxTests` `ChatFixTask1SidebarGridAcceptanceTests` は 2 モード前提へ、`AcceptanceComposerDestinationLabelTests` は討論の宛先ケースだけを削除。

### 検証メモ（全段共通の手順）

- パッケージテストは `--no-parallel` で回す。並列では `AcceptanceSessionTitlePersistenceTests` の `capturingStandardError` が、並行テストの子プロセスに stderr の書き込み端を継承されて無期限に待つ（既存の不具合。2026-09-24 に `sample` で特定。変更前のコードでも同じ作り）。`MidTurnPersistenceWhitebox` の 500ms しきい値も負荷で落ちる（変更前の全体実行でも再現）。
- xcodegen が未導入のため、生成済みの `Phlox.xcodeproj` と `App/Info.plist` をメイン checkout から複製してビルドしている。App/ にファイルを足す段では再生成が必要。

## P2 ウィンドウ骨格（01 Main Window）

### 対応表

| 機能一覧（01 の対応表） | 内容 | 実装箇所 |
|---|---|---|
| ツールバー（52pt） | 中央とインスペクタの上に渡る 1 行。単体とグリッドで並びを変えない | `DashboardToolbar.swift`（`DashboardToolbar`）。オーバーレイ方式をやめ、`DashboardView` の縦並びの 1 行目に置いた |
| 信号とツールバーの高さ揃え | 信号をツールバーの縦中央に置く | `WindowChromeConfigurator.swift`（空の `NSToolbar` を付けて unified の高さにする）。ツールバー上の SwiftUI ボタンが押せることを実機で確認 |
| 選択中セッション名 | タイトル＋サブタイトル（花名 · 短縮 ID · プロジェクト）。未選択時はプロジェクト名 | `DashboardToolbar.titleBlock` / `subtitle(for:)` |
| Git worktree 隔離メニュー | タイトル右「worktree 隔離 ▾」、プロジェクト選択時だけ。1280pt 未満はアイコンだけ | `DashboardToolbar.worktreeMenu`（`DashboardView.projectIsolationMenu` から移動） |
| 表示モード切替 | ツールバー中央の 2 セグメント（文字つき、960pt 未満はアイコンだけ）。⌃⌘1 / ⌃⌘2、⌃⌘G は巡回 | `ViewModeToggle`、`PhloxApp.ViewCommands` |
| 対応待ち（新規） | 「対応待ち n」→ 待ち時間の長い順の一覧。↑↓・↩・⌥⌘↩、行の 許可 / 拒否 / 回答する… / 開く、末尾に完了の未読とキー案内。⌘J / ⌥⌘J | `AttentionListPopover.swift`（`AttentionButton` / `AttentionListPopover`）、`AttentionQueue.swift`（並びと巡回）、`SessionCommands` |
| 待ち時間 | 今の状態に入った時刻 | `ControllableSession.statusEnteredAt`（`ChatSessionViewModel` / `SessionViewModel` が状態の種類が変わったときに記録。`SessionStatus.hasSameKind(as:)`） |
| 使用量チップ | インスペクタの開閉に関係なく表示。ゲージ → 文字 → 最小の残量 1 つ。残り 20% 未満は琥珀色と ▲。押すとインスペクタを開く | `UsageTopBarView`（`density` で開始段階を決める）、`UsageDisplay.isLowRemaining` / `minimumRemainingPercent`、`DashboardToolbar.usageChip` |
| インスペクタ開閉 | ツールバー右端。⌃⌘I | `DashboardToolbar.inspectorToggleButton`、`ViewCommands` |
| サイドバー開閉 | サイドバー上端。隠しているときはツールバー左（信号の右）に対応待ち件数つきで出す。⌃⌘S | `SidebarToggleButton`、`DashboardView.sidebarColumn` |
| 設定・エージェント管理 | サイドバー下端へ移動（メニューとキーは維持） | `DashboardView.sidebarFooter` |
| グリッドの絞り込みサマリ・解除・表示セッション選択・レイアウト | ツールバーから、グリッドのときだけ出す表示範囲バーへ移動。範囲外の対応待ち件数を追加 | `GridModeBar.swift` |
| サイドバー / インスペクタの幅 | 260（220–360）/ 280（260–340）。境界ドラッグ。中央 480pt を割り込まない | `PaneWidthPolicy.resolve` / `draggedSidebarWidth` / `draggedInspectorWidth`（`DSLayout` の範囲を使う） |
| 狭い幅での縮退 | 中央が 480pt を割るとインスペクタを重ね表示、それでも足りなければサイドバーを自動で隠す（⌃⌘S で一時表示）。最小ウィンドウ 720×520 | `PaneWidthPolicy.resolve`、`AppRouter.sidebarAutoHidden` / `sidebarPeeking` / `toggleSidebar()`、`PhloxApp` の `minWidth: 720, minHeight: 520` |
| ツールバーの縮退 | 1280 / 960pt で 3 段階 | `ToolbarDensity.forWindowWidth` |
| メニューとキー | 表示: 単体 ⌃⌘1・グリッド ⌃⌘2・次の表示モード ⌃⌘G・サイドバー ⌃⌘S・インスペクタ ⌃⌘I。ファイル: プロジェクトを追加 ⌘O。セッション: 次の対応待ちへ ⌘J・対応待ちの一覧 ⌥⌘J、会話を Markdown でコピー ⌥⇧⌘C。⌘B・⌥⌘B を廃止 | `PhloxApp.swift`（`ViewCommands` / `SessionCommands` / `.newItem`）、⌘O は `AppRouter.addProjectRequested` 経由で `DashboardView.chooseProjectDirectory` |

### 決定・食い違い

- **ドロワーの削除は P3 へ 1 段ずらした**。P2 で消すと、子タブ（P3）ができるまでターミナルとエディタに入れなくなる（機能の欠落）ため。ドロワーは残し、キーだけ確定版の ⌃⌘T / ⌃⌘E に変えた（⌥⌘T は macOS 標準の「ツールバーを表示/隠す」と重なる）。P3 で子タブに置き換えて `PanelDrawerLayout` ほかを消す。
- **状態は文字で示す（P1 の決定を維持）**。モックは対応待ちボタンと一覧の行に状態の記号（ひし形・? など）を出すが、「一覧の状態はアイコンでなく文字」の指示に合わせ、ボタンは「対応待ち」＋件数、行は `StatusLabel` の文言にした。
- **対応待ちが 0 件のときはボタンを押せない**。一覧の空表示はデザインに無い（未確定）ため、新しい文言を作らず開かない形にした。
- **⌘J の順は一覧と同じ（待ち時間の長い順）**。デザインは「次の対応待ちへ」とだけ書いており順を明記していないため、一覧に合わせた。
- **対応待ちの数え方**: 承認待ち・質問待ち・エラー・無応答（無応答の判定は P5）。完了の未読は数えない。エラーは従来の `SessionAttentionPolicy`（サイドバーの赤）には入っていないが、01 B1 の定義どおり対応待ちに入れた。Dock バッジは従来どおり未読の完了数（01 G3 の分岐。現行を既定）。
- **01 D2（1024pt でインスペクタ重ね表示）とのずれ**: 1024 − 261 − 281 = 482pt で中央 480pt を満たすため、仕様の文言どおりの判定では 1024pt ではまだ横に並ぶ。数値の規則（480pt）を優先した。
- **使用量チップの色**: 色は対応待ちにだけ使う方針に合わせ、ツールバーのチップは無彩色、残り 20% 未満だけ琥珀色にした。インスペクタ側の緑→赤のゲージ（`UsageDisplay.usageColor`）は P8 で扱う。リセット間近でラベルを赤くする既存表示はそのまま（P8 で再検討）。
- **使用量チップを押すとインスペクタを開くだけ**。「使用量」タブへの切替はインスペクタのタブ化（P8）で入れる。
- **E1 の「開く」でグリッドの範囲外のセッションを一時追加する動き**は P7（グリッド）で入れる。今はセッションを選ぶだけ（範囲内ならそのタイルにフォーカス）。
- **⌘J と一覧の「開く」の後始末**: 入力欄がフォーカスを持ったままだと、グリッドではそのタイルが選択を取り返すため、選ぶ前にメインウィンドウのフォーカスを外す。移動先のタイルの入力欄へフォーカスを移すことと、範囲外のセッションを一時追加することは P7。
- **一覧から直接返せるのはチャット型の承認待ちだけ**。PTY 型の承認待ちは端末の中でしか答えられないため「開く」だけを出す。無応答の「中断」は無応答の判定と一緒に P5 で入れる。
- **サイドバー最上部の「対応待ち」セクション（01 B1 の 2）** は P4（サイドバー）で入れる。
- **ドロワーは確定幅（保存値）を先に取ってから 3 ペインを決める**。ドロワーを縮めれば並べられる幅でもサイドバーが先に隠れることがある。ドロワー自体を P3 で消すため、ここでは直さない。
- **後の段へ回したキー**: ⌘N の種別ポップオーバー（旧 ⇧⌘N / ⌥⌘N の廃止を含む）は P9、⌘1–9・⌘T・⌘P・⌘\・⌃Tab・⌘W の意味の変更は P3/P7、⌘. ・⌥⌘↩ / ⌥⌘⌫（メニュー）は P5/P6、⌘+ / ⌘0 は P5。

### テストの更新

- 削除（オーバーレイ方式のトップバーの契約）: `AcceptanceTopBarInsetTests` / `TopBarInsetPolicyTests`（`TopBarInsetPolicy`）、`TrailingTopBarLayoutWhiteboxTests` / `TrailingTopBarLayoutAcceptanceTests`（`TrailingTopBarLayout`）、`PanelIntegrationWhiteboxTests.topBarWindowWidthDoesNotSubtractDrawerWidth`（ツールバーを縦並びにしたのでドロワー幅と交わらない）。
- 置き換え（旧契約を 01 D が上書き）: `AcceptancePaneWidthPolicyTests` / `PaneWidthPolicyWhiteboxTests`（最小幅 240/240/400 で両ペインを縮める旧契約）→ `PaneLayoutPolicyTests`（220–360 / 260–340、中央 480、重ね表示→自動で隠す）。`HeaderUsageVisibilityAcceptanceTests` の「インスペクタ表示中はヘッダーに出さない」ほか 3 件と `HeaderUsageWhiteboxTests` の 1 件（`showsTopBarUsage`。01 G2 で条件を削除）→ 残量の判定のテスト 3 件。
- キーの変更に追従: `AcceptanceTerminalPanelWiringTests` / `AcceptancePanelIntegrationTests`（⌥⌘T/E → ⌃⌘T/E）、`PhloxUITests/PanelUITests`、`UITests/ViewModeAccessibilityTests` / `ViewModeHelpObservationTests`（P1' で残っていたチームビューを除き 2 モード・⌃⌘1/⌃⌘2 を追加。UI テストは未実行）。
- 新設: `AttentionQueueTests`（対象の絞り込み・待ち時間順・⌘J の巡回）、`ToolbarDensityTests`、`SidebarToggleTests`（幅が無いときの一時表示、狭い窓で手動で隠したサイドバーを 1 回で出す）。
- 参照先の移動: `AcceptancePaneLayoutPresetMenuTests.topBar_replacesTheGridColumnsSegmentWithThePresetMenu` は、プリセットメニューの移動先 `GridModeBar.swift` を読むように変えた（検査内容は同じ）。

### 検証

- パッケージテスト（`--no-parallel`）: DesignSystem 188・AgentDomain 545・SessionFeature 1045・DashboardFeature・AppBootstrap 161・TerminalUI 79 が合格。ControlServer は 158 件中 1 件（`AcceptanceSpawnProjectIdTests` の HTTP 60 秒タイムアウト）が全体実行で落ち、単独再実行で合格（P2 で ControlServer は未変更。P1 から出ている既知の不安定テスト）。App の Debug ビルドは成功。
- AppBootstrap は、削除したファイルを覚えたビルドキャッシュで「missing inputs」になったため `swift package clean` してから実行した。
- Debug 版での目視（スクリーンショット）: ダーク 1206pt（単体・グリッド・インスペクタ横並び）、900pt の最小段階、ライト＋英語。ツールバー上のボタンのクリック、⌃⌘1 / ⌃⌘2、⌥⌘J → ↓ → ↩ を合成入力で確認。UI テスト（XCUITest）は実行していない。

## P3 タブ（02 案 C）

### 対応表

| 機能一覧（02 案 C） | 内容 | 実装箇所 |
|---|---|---|
| C1 上段＝セッションのタブ | プロジェクトのセッションを並べる。エージェントの頭文字（Cl / Cx / Cu）・題名・対応待ちのときだけ状態の文言・✕（選択中とホバー時）。✕ はタブを閉じるだけでセッションは残る | `Tabs/SessionTabBar.swift`（`SessionTabBar` / `SessionTabButton`）、`AgentDescriptor.tabInitials` |
| C1 並びと開閉をプロジェクトごとに保存 | 保存した並び → 新しいセッションを末尾、閉じたタブは出さない。選ぶと再び出る。ドラッグで並べ替え | `Tabs/SessionTabs.swift`（`SessionTabsSnapshot` / `SessionTabStore`、UserDefaults `phlox.sessionTabs.v1`）、`SessionTabBar.moveTab` |
| C2 下段＝そのセッションの子タブ | 会話（閉じられない）・ターミナル・変更・ファイル。未保存のファイルは ✕ の代わりに点 | `Tabs/SessionTabsContainer.swift`（`ChildTabBar` / `ChildTabButton`）、`SessionTabLayout` |
| C2 子タブの中身（07 の下半分を流用） | ターミナル＝セッションの worktree で起動。変更＝07 の一覧と差分。ファイル＝編集・保存（競合時は上書き確認） | `UserTerminal/SessionTerminalStore.swift`、`Editor/EditorPanelView.swift`（見出しを外して子タブに収めた）、`Tabs/FileTabDocument.swift` と `FileTabView` |
| C3 分割 | ⌘\ で右に分割／解除、子タブを右半分へドラッグして分割。各 320pt 以上、境界ドラッグで比率を変えて保存。フォーカス側を枠で示す。⌃Tab / ⌃⇧Tab で子タブを巡回 | `ChildTabPanes`、`SessionTabLayout.splitRight` / `toggleSplit` / `cycle(by:)`、`PhloxApp` の `TabCommands` と ⌘¥ の監視 |
| C4 新しいタブの選択肢 | 「このセッションに開く」: 会話・ターミナル ⌃⌘T・変更一覧・差分 ⌃⌘E・ファイルを開く… ⌘P・エージェント管理 ⇧⌘,。↑↓・↩ | `NewTabChooser`（上段の＋・下段の＋・⌘T で同じもの） |
| C5 右端の固定タブ | 共通ターミナル（ホームで開く）・エージェント管理 | `SessionTabBar.pinnedTab`。共通ターミナルは旧ドロワーのシェルをそのまま使う |
| C7 あふれたときの対応待ち | 見えない位置のタブに対応待ちがあれば「隠れたタブに ○○ n」。押すと最初のものへ移る | `HiddenAttentionSummary.make`、`SessionTabBar.hiddenAttentionBadge` |
| 13 Review ⌘W | 子タブを閉じる（動いているシェル・未保存のファイルは確認）。会話タブではセッション削除の確認。確認はキャンセルが既定、破壊側は赤 | `AppRouter.requestClose()` / `TabRequest`、`SessionTabStore.closeTarget`、`DashboardView.shellWithTabDialogs` |
| 13 Review ⌘1–9 | 単体＝上段のタブ、グリッド＝タイル | `DashboardViewModel.numberedTabSessionIDs(router:)`、`TabCommands` |
| 旧ドロワー（07 のパネル） | 削除。中身は子タブへ移動 | `PanelDrawerLayout.swift` と `DashboardView` のドロワー配置・つまみ・予約幅を削除。`AppRouter.terminalPanelVisible` / `editorPanelVisible` を削除 |

### 決定・食い違い

- **エージェント管理と設定は別ウィンドウのまま**。上段右端の固定タブはウィンドウを開くボタンとして置いた（タブの中に埋め込むとウィンドウ側の機能と二重になるため）。
- **共通ターミナルの名前と場所**: 旧ドロワーのホームのシェルを「共通ターミナル」として残した。プロジェクトが無くても開けるよう、単体表示は常にタブの枠で包む。
- **⌘T・上段の＋・下段の＋は同じ C4 の選択肢**。モックのソースで ⌘T の見出しが「新しいタブ（⌘T）」で C の項目を出しているため。
- **ターミナルを閉じる確認は、シェルが動いていれば必ず出す**。「中で何かが動いているか」を知る手段（子プロセスの取得）が無いため。
- **ウィンドウが狭いと分割しない**（中央が 641pt 未満。320pt×2 を割るため）。900pt の窓ではサイドバーを出したままだと分割できない。
- **グリッドのタイルのタブ（C3 のグリッド側）と、グリッドでの ⌘W＝タイルを外す**は P7。いまのグリッドの ⌘W は確認付きのセッション削除。
- **編集は変更タブからファイルタブへ移した**。変更タブは一覧と差分だけにし、「ファイルタブで編集」で開く。
- **Codex の頭文字は Cx**（組み込みの 3 種は固定の対応、カスタムは表示名の先頭 2 文字）。
- **作業場所を変えたセッションは、ターミナルとファイルタブを作り直す**（旧い場所のシェルを止め、下書きを捨てる。作業場所の変更は「進行中の作業は失われます」の確認を経る）。
- **セッション削除の確認に未保存のファイル名を出す**。
- **子タブを切り替えたら入力欄のフォーカスを外す**（切り替え前の入力欄がキーを取り続けるため）。
- **ポップオーバーには言語設定を渡し直す**。macOS の popover は画面の `locale` を引き継がず、アプリ内で英語にしても日本語で出ていた。
- 既存のまま残した未翻訳: `EditorPanelViewModel` の状態文言、セッション削除の見出し（P10）、`String(localized:)` で OS の言語に従う P2 以前の文言（表示モード切替など）。
- UI テストの `IsolatedPhloxApplication` は旧ドロワーの UserDefaults を保存・復元したまま（読まれないだけで害は無い）。

### テストの更新

- 削除（ドロワーの契約）: `AcceptancePanelRouterTests`（開閉フラグ）、`PanelIntegrationWhiteboxTests` のドロワー幅の検査。
- 追従: `AcceptanceTerminalPanelWiringTests` / `AcceptancePanelIntegrationTests`（⌃⌘T / ⌃⌘E → `openChildTab`、配線先が `SessionTabsContainer.swift`）、`SessionScopedChangesTests`（`EditorPanelView(viewModel:)`）、`PhloxUITests/PanelUITests`（セッション未選択での ⌃⌘T＝共通ターミナル、⌃⌘E は無効。UI テストは未実行）。
- 新設 `SessionTabsTests.swift`: 子タブの開閉・選択・巡回・分割、並びの保存と閉じたタブ、並べ替え、隠れた対応待ちのまとめ、⌘W の行き先、⌘1–9 の対象、セッションのターミナル（worktree で起動・同じ場所では使い回す・作業場所が変わったら作り直す・閉じると止まる）、⌘P の相対パス。

### 検証

- パッケージテスト（`--no-parallel`）: DesignSystem・AgentDomain・SessionFeature・DashboardFeature 1579・AppBootstrap 161・ControlServer 158・TerminalUI 79 が合格。App の Debug ビルドは成功。`git diff --check` は問題なし。
- Codex（gpt-6-sol high）の独立レビュー: 高 2・中 4 の指摘。作業場所の変更・未保存のまま削除・並べ替え・閉じてすぐ開く・アプリ内の英語設定の 5 件は修正した。UI テストの追加は見送った（UI テストをこの環境で走らせていないため）。
- Debug 版での目視（スクリーンショット）: ダークで上段・下段・隠れた対応待ち、⌃⌘T の worktree のターミナル、分割とフォーカス枠、⌃Tab、⌘¥ で解除、再起動後の配置の復元。ライト＋英語で C4、変更タブの差分、「ファイルタブで編集」、⌘W の段階（ファイル → 変更 → 会話 → 削除確認を Esc でキャンセル）。アプリ内の英語設定だけで、タブ・選択肢が英語になることを確認。
- 目視していないもの: 子タブのドラッグによる分割、上段タブのドラッグ並べ替え、⌘P のファイル選択画面。XCUITest は実行していない。

## P4 サイドバー（03 Sidebar）

### 対応表

| 機能一覧（03 の対応表） | 内容 | 実装箇所 |
|---|---|---|
| 対応待ちの節（新規） | 最上部に固定（スクロールしない）。「対応待ち n」＋「待ち時間順」、行は タイトル・状態の文言・「プロジェクト · エージェント」・待ち時間。未読の完了は「未読の完了 n 件」1 行にまとめ、押すと展開（1 件ならそのセッションを開く） | `DashboardSidebarView.attentionSection` / `SidebarAttentionRow`。並びと対象は P2 の `attentionEntries`・`unseenCompletionNodes` をそのまま使う |
| プロジェクト一覧表示 | 「プロジェクト」節。スクロール中はプロジェクト行を上端に貼り付ける | `DashboardSidebarView.tree`（`LazyVStack(pinnedViews: .sectionHeaders)`） |
| プロジェクト追加 | 節見出しの ＋（⌘O）・空状態の「フォルダを追加… ⌘O」 | `projectsHeading` / `emptyState` |
| 展開 / 折りたたみ | シェブロン・←→。畳んだ行に中身の要約 | `SidebarProjectRow`、`SidebarCollapsedSummary`、`SidebarRowMeta.project` |
| プロジェクト選択・グリッド絞り込み（統合） | 行クリックで選択し、そのプロジェクトがグリッドの表示範囲になる。グリッドでは行末に範囲の印。⌘クリックで解除 | `AppRouter.showProject` / `selectProjectFromSidebar` / `clearProjectScope` |
| プロジェクト名変更 | ⋯ / 右クリック / ↩ → 行の中で編集（アラート廃止）。変わるのは表示名だけ | `SidebarRenameField`、`DashboardSidebarView.beginRename` / `commitRename` |
| プロジェクト削除 | ⋯ / 右クリック / ⌘⌫（サイドバーにフォーカスがあるとき）→ 確認 | `projectMenu`、`handleKey`（確認は従来の `pendingProjectDeletion`） |
| worktree 隔離（F4） | プロジェクトの ⋯ / 右クリックにも「git worktree で隔離する」 | `projectMenu`（`setWorktreeIsolationEnabled`） |
| 新規セッションメニュー | プロジェクト行の ＋・下端「＋ 新規セッション ⌘N」 | `SidebarProjectRow` の ＋、`DashboardView.sidebarFooter`（中身は従来の `newSessionMenuItems`。表は P9） |
| 未割当セッション | 「その他（プロジェクト未割当）」節。プロジェクトが無く未割当だけ残るときは「その他」だけを出す（従来は空状態で隠れていた） | `DashboardSidebarView.tree` |
| セッション行表示 | タイトル・右端（頭文字と状態）。待機は経過時間（1 分ごと）、それ以外は状態の文言、対応待ちは状態色 | `SidebarSessionRow`、`SidebarRowMeta.session`、`SidebarRelativeTime.label(from:to:locale:)` |
| セッションツリー | 1 段 16pt の字下げ・縦の案内線・左余白のシェブロン。畳むと「+n」と子孫の要約 | `SidebarSessionRow.guides` / `chevron`、`SidebarRowMetrics` |
| セッション選択 | 行クリック・↑↓・対応待ちの行。選択は accent の淡い面（左マーカーと太字は廃止） | `SidebarRowEmphasis`、`SidebarNavigation.step` |
| ホバー強調 | グレーの面＋⋯（右クリックと同じメニュー） | `SidebarRowEmphasis`、`SidebarRowIcon` |
| 要注意（未読完了）表示 | 太字＋点・対応待ちの節の「未読の完了 n 件」・畳んだ行の「未読 n」 | `SidebarRowEmphasis.nameWeight`、`SidebarSummaryText` |
| セッション名変更 | 右クリック / ↩ / メニューバー「セッション › 名前を変更…」→ 行の中で編集。空欄で自動の名前に戻す | `SidebarRenameField`、`AppRouter.SidebarRequest.renameSession` |
| 割り当て・移動（F2・F3） | 「プロジェクトを移動 ▸」／未割当は「プロジェクトに割り当てる ▸」に、ほかのプロジェクトと「フォルダを選択…」。メニューバーの「セッション」メニューにも同じもの | `sessionMenu`、`PhloxApp.SessionCommands`、`DashboardViewModel.moveSession`（未割当の割り当てを許可） |
| 再起動の確認（F9） | 移動は「「X」を P へ移動しますか?」、フォルダはパネルで選んだ後に「「X」を ~/path で再起動しますか?」。既定はキャンセル、実行側は破壊的 | `DashboardView.shellWithTabDialogs`（`pendingMove` / `pendingFolderChange`） |
| セッション削除 | 右クリック / ⌘⌫（サイドバーにフォーカスがあるとき）/ 単体の ⌘W → 確認 | `sessionMenu`、`handleKey` |
| 空状態 | S3 の文言とボタン | `emptyState` |
| runningBreakdown / runningSessionCount（3.1） | プロジェクト行右端「n 実行中」 | `SidebarProjectRow.trailingMeta`（P1 の `RunningCountBadge`） |
| キーボード | ↑↓ 移動・←→ 畳む/開く（← は親へ）・↩ 名前を変更・⌘⌫ 削除・文字入力で頭出し | `DashboardSidebarView.handleKey`、`SidebarNavigation` |

### 決定・食い違い

- **並べ替え（F10）は入れない**。03 で「候補・未配線」。`reorderSession` は入れ替え（swap）で 03 の挿入とも違うため、現行（呼び出し元なし）のまま。⌥⇧⌘↑↓ も未割り当て。
- **内部セッション（G3）は現行どおり**。展開したときの子行と「n 実行中（内部 m）」は変更前のサイドバーと同じ描画元のまま。
- **状態は記号でなく文字**（P1・P2 の決定）。畳んだ行の「◆1 ●1」は「承認待ち 1 · 未読 1」のように状態色の文字、実行中の回転する円は出さず「実行中」の文字にした。
- **新規セッションの表（F5）と ⌘N は P9**。いまは従来のメニューをプロジェクト行の ＋ と下端のボタンから開く。
- **グリッドで範囲中のプロジェクトをもう一度押すと範囲を外す**（従来のトグル）。凍結受け入れテスト `AcceptanceSingleModeProjectSelectTests` が要求するため残し、⌘クリックでの解除を足した。↑↓ で選んだときはトグルしない。単体表示でも行を選ぶとグリッドの範囲になる（03「行クリックで選択し、そのプロジェクトがグリッドの表示範囲になる」）。
- **入力先**: 行の選択でターミナル・入力欄が自分で入力先を取る既存の動きは変えていない。キー（↑↓・←・頭出し）で選んだ直後 0.5 秒だけは一覧に戻し、続けて動けるようにした。クリックで選んだとき、ほかをクリックして名前を確定したときは戻さない。
- **行の ⋯ はホバー中だけ**（モックどおり）。キーボードだけの操作は ↩（名前）・⌘⌫（削除）・メニューバーの「セッション」メニュー（名前・移動）で届く。VoiceOver は行の「メニューを表示」で全項目に届く。
- **名前変更の案内は行の中に出す**。モックの吹き出し（行の下に重ねる）は、下の行の文字と重なったため。
- **プロジェクト名の空欄確定は変えない**（従来どおり）。03 は「プロジェクトも同じ方式」とあるが、空欄時の自動の名前（フォルダ名に戻すか）は書いていないため。
- **フォルダ選択の確認を選んだ後に移した**（F9 が行き先を示す確認のため）。従来の「プロジェクトを変更しますか?」の事前確認は削除。グリッドのタイルからの作業場所変更も同じ流れになる。同じフォルダを選び直して再起動したときは、子タブ（ターミナル・ファイル）はそのまま残す（作業場所が変わらず使い続けられるため）。
- **移動・作業場所の変更は、成功を確かめてから子タブを片付ける**（再起動の準備に失敗したら元のまま残す）。
- **移動できるのは従来どおりターミナル型のセッションだけ**（`node.pty != nil`）。
- **弱い文字（fg3）は確定値に戻さない**。P1 では「P4 で旧注意面をやめたら戻す」としたが、実測するとデザインの #75757B はサイドバーの地 #F2F2F4 の上で 4.09:1、選択面の上で 3.4:1 前後で、旧注意面が無くても 4.5:1 に届かない。`AppTheme.designText` の補正（本文色へ寄せる）を残す。デザイン側の確認事項。
- 選択中のセッションが属するプロジェクト行は塗らない（`selectedProjectID` はセッション選択では変えないため）。モックは両方を塗るが、選択の意味を変えるので現行どおり。
- `SidebarRelativeTime` に英語表記（now / 5m / 3h / 2d / 1mo / 1y）を足した。日本語は従来どおり。

### テストの更新

- 置き換え: `AcceptanceSidebarRowEmphasisTests`（選択の左マーカーと太字・未読の塗りの契約 → 03 の「選択 = accent の面、未読 = 太字、背景は選択とホバーだけ」）。
- 削除: `WorkspaceSidebarPolicyAcceptanceTests.workspaceSidebar_projectIconPolicy_hiddenByDefault_dimWhenUnseenCompletion`（`ProjectIconPolicy` を 03 G1 で畳んだ行の要約に置き換えたため）。代わりに要約と右端の表示規則を `SidebarNavigationTests.swift` で検査する。
- 新設 `SidebarNavigationTests.swift`: ↑↓ の移動と端・頭出し、畳んだ行の要約、行の右端に出すもの、プロジェクト行の選択とグリッドの範囲（`showProject` はトグルしない・⌘クリックで解除）、経過時間の英語表記。`WorkspaceManagementTests.moveSession_assignsUnassignedSessionToProject`（未割当の割り当て）。

### 検証

- パッケージテスト（`--no-parallel`）: DesignSystem 188・AgentDomain 545・SessionFeature 1045・DashboardFeature 1598・AppBootstrap 161・TerminalUI 79 が合格。ControlServer は初回に `AcceptanceSpawnProjectIdTests` が HTTP のタイムアウトで 1 件落ち、再実行で 158 件合格（P2 から出ている既知の不安定テスト。P4 で ControlServer は未変更）。App の Debug ビルド成功、`git diff --check` 問題なし。AppBootstrap はビルドキャッシュのため `swift package clean` の後に実行。
- Codex（gpt-6-sol high）の独立レビュー: 高 3・中 4。移動失敗時の子タブ破棄・フォーカスの奪い返し・キーボードからメニューに届かない・フォルダ選択後の確認なし・読み上げの言語・表示規則のテスト不足を修正。内部セッションは現行どおりと確認。再レビューで 7 件とも解消、新しい指摘 1 件（同じフォルダでの再起動）は上の決定のとおり。
- Debug 版での目視（スクリーンショット）: ダークで対応待ちの節・畳んだ行の「エラー 2 · 8」・展開した行（頭文字と経過時間・状態の文言）・↑↓ と → での移動（画面が切り替わっても一覧に入力先が残る）・↩ の名前変更と Esc の取り消し・メニューバー「名前を変更…」で畳まれたプロジェクトが開いて編集に入る。ライトで行の中の名前変更と案内・右クリックのメニュー。英語で「Needs you / Longest wait first / Projects / 18d / error / New Session」と名前変更の案内。
- 目視していないもの: 移動のサブメニューと F9 の確認（Debug 版のセッションがすべて会話型で、ターミナル型を新しく起動すると実エージェントが動くため起動しなかった）、長いリストでのプロジェクト行の貼り付け（最小の窓でもあふれなかった）、⌘クリックでの解除、VoiceOver の実操作。XCUITest は実行していない。
