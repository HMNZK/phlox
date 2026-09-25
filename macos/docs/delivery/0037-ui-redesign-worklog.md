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

## P5 会話画面（04 Session Chat）

### 対応表

| 機能一覧（04 の対応表） | 区分 | 内容 | 実装箇所 |
|---|---|---|---|
| メッセージ・Markdown・コード（A1・C1） | 変更 | エージェント側の要素を 1 本の字下げ列（30pt）に揃え、ユーザー発言の後に 20pt の頭文字を置く。本文・コピーの動きは従来どおり | `ChatTranscriptView.agentColumn` / `TranscriptAgentAvatar`、`AgentDescriptor.tabInitials`（DesignSystem へ移動） |
| 推論・コマンド・ファイル変更・タスクリスト（A1・C2） | 既存のまま | 既定の開き方は未確定（下記）のため従来どおり | — |
| エラー・ユーザー質問・承認バナー（A1・B4） | 既存のまま / P6 へ | 承認バナーの入力欄直上への移動は P6 | — |
| 思考中・直近アクション要約・接続待ち・圧縮中（A1・B1・B6） | 変更 | 思考中の行を「orb・状態語・『X を実行中 · 38 秒』」に。要約は最後のユーザー入力以降のコマンド / ファイル変更、無ければ推論の見出し、5 秒未満は出さない。状態語は xcstrings から表示言語で引く | `ThinkingIndicatorCell`、`ChatRecap.summary`、`ChatSessionViewModel.thinkingRecap`、`AgentActivityState.orbLabel(locale:)`、`AppLocalizedString` |
| ハング検知・経過時間・中断（B5） | 変更 | 120 秒で「無応答」状態（紫）。思考中の行・ヘッダ・タブ・サイドバー・対応待ちの一覧に「無応答 m:ss」（1 秒更新）、行と一覧に「中断」。イベント受信・状態変化で即解除 | `ChatSessionViewModel.isStalled` / `stalledSince` / `updateStalled`、`SessionNode.isStalled` / `stalledSilence`、`StallClock`、`AttentionListPopover`、`SidebarRows` |
| ターンのコスト（TurnUsage） | 変更 | 右寄せ 1 行にトークン内訳（入力 / 出力 / キャッシュ読込）とコンテキスト % を追加。金額の無い Codex はターン最後の応答の下に内訳だけ出す | `TurnCostCell`、`ChatSessionViewModel.turnUsageByItemID` |
| サブエージェント（C3） | 変更 | 帯をセッションヘッダ右へ移動。マーカー・ドロワーは従来どおり | `ChatSessionHeader.subAgentChips`（`SubAgentStripRow` を再利用） |
| Codex のプラン・子スレッド・停止（D1） | 既存のまま | 上端の重ね表示のまま（下記）。中身が空のときの 8pt の空カードは消した | `CodexSessionSurface.hasContent` |
| 中断・Esc の優先順・巻き戻し・下書き（C4） | 変更（一部） | メニューバー「セッション › 中断」⌘. を追加（実行中だけ有効、共通ターミナル表示中は無効）。Esc の優先順と巻き戻しは従来どおり | `PhloxApp.SessionCommands` |
| 履歴から再開（C5・B3） | 既存のまま | — | — |
| 自動スクロール追従（B7） | 変更 | 読み戻して追従が外れたら「↓ 最新へ · 新着 n · End」。新着はメッセージ・質問・エラーだけ数える。End キーでも戻る。セッション切替でリセット | `ChatAutoFollowController.isDetached`、`JumpToLatestButton`、`ChatTranscriptView.jumpToLatest` |
| 以前のメッセージを表示（B7） | 既存のまま | — | — |
| テキスト選択の方針（C1） | 既存のまま | `ChatTextSelectionPolicy` は変更なし | — |
| 書き出し / Markdown でコピー（C6） | 変更 | ヘッダのボタンから選択肢（推論・コマンド出力・タイムスタンプ、アプリ全体で記憶）・コピー ⌥⇧⌘C・書き出す…。⇧⌘E は従来どおり | `ChatExportPopover`、`ChatTranscriptExportOptions.stored`、`ChatTranscriptExportAction`（App から SessionFeature へ移動） |
| セッションヘッダ（命名 3 段階・状態・種別・作業ディレクトリ・ブランチ） | 変更（新設） | 56pt。タイトル（ダブルクリックで名前変更）と命名タグ（花名 / 自動 / 手動は無し）、エージェント · モデル · 推論の強さ · 作業ディレクトリ · ブランチ（表示中 2 秒ごとに読み直す）、状態（対応待ち 4 状態だけ色の面） | `ChatSessionHeader` |
| PTY 型の単体表示・信頼確認・対話質問の検知（D3） | 既存のまま | — | — |
| 描画の性能 | 既存のまま | `.equatable()` の比較に使用量を追加しただけ | `ChatItemView.==` |
| 文字サイズ（13 Review ⌘+ / ⌘− / ⌘0） | 変更 | フォーカス中の領域だけ変える（ターミナル子タブ・PTY・共通ターミナル → 端末、会話 → 会話の倍率、セッション無し → 両方）。⌘0 で実寸 | `DashboardViewModel.fontSizeTarget` / `adjustFontSize` / `resetFontSize`、`PhloxApp.FontSizeCommands` |

### 決定・食い違い

- **入力欄の最大幅は 800pt のまま**。04 は 760pt だが、凍結受け入れテストが 800pt を要求する（760 にすると 18 件落ちる）。デザイン側の確認事項。
- **名前変更で空欄確定すると短縮 ID の表示になる**（凍結テスト `AcceptanceSessionTitleStateTests`）。花名に戻すことはしない。P4 の名前変更の案内もこの動きに合わせて「空欄で短縮 ID 表示に戻す」に直した。
- **トークン内訳は保存しない**。復元した会話はコストだけ出る（`ChatItem.turnCost` の形を変えないため）。
- **ツールバーのタイトルは 01 のまま**。04 はヘッダと同じ内容を 1 行に縮めるとするが、01（P2）の決定を優先した。
- **Codex の面は上端の重ね表示のまま**。会話の中へ組み込む形は描画元の組み替えが大きく、見た目以外の差が無いため。
- **承認バナーの移動は P6**。
- 未確定（現行どおり・画面に出さない）: カードの既定の開き方（04「案」の行）、B3 の `completed(exitCode)` の意味、Codex の画像添付の可否。

### テストの更新

- 凍結テストは変更していない（一度入れた変更は戻した）。
- 新設 `DashboardFeatureTests/ChatStallPropagationTests.swift`: 無応答の伝播（タブ・待ち時間の起点）、完了・イベント受信での即解除、質問待ちは無応答に数えない、金額の無い使用量が最後の応答に付く、文字サイズの対象（共通ターミナルを含む）。
- 新設 `SessionFeatureTests/SessionChatRedesignTests.swift`: トークン数の短い表記・コンテキスト %・内訳の有無・要約の規則・追従が外れる条件。

### 検証

- `.claude/verify.sh`（DesignSystem・AgentDomain・SessionFeature・DashboardFeature・App の Debug ビルド）合格。AppBootstrap 161・ControlServer 158・TerminalUI 79 が合格（`--no-parallel`）。orb の読み上げ変更後に DesignSystem 188・SessionFeature 1051・DashboardFeature 1603 合格。`git diff --check` 問題なし。AppBootstrap はビルドキャッシュのため `swift package clean` の後に実行。
- Codex（gpt-6-sol high）の独立レビュー: 高 1・中 4・低 2（共通ターミナル表示中の ⌘. と文字サイズ・金額の無い使用量・ブランチの更新・無応答の秒表示・状態語の文字列管理・新着の数え方）。再レビュー 2 回で全件解消。途中で出た低 1 件（無応答の解除が 1 秒周期待ち）も解消。
- Debug 版での目視（スクリーンショット）: ダークでヘッダ（「Claude Code · Fable 5.1 · high · パス」・待機）・エラーの状態・頭文字と字下げ。ライト＋英語でヘッダのブランチ・エラーの状態・書き出しの選択肢。⌘+ / ⌘0 がターミナル子タブでは端末だけ（13→15→戻る）、会話タブでは会話の倍率だけ（1→1.1→戻る）を変える。
- テスト内の描画（PNG、ダーク・ライト）: 無応答の行・実行中の要約行・使用量の行・「↓ 最新へ」。英語の文言はテストのバンドルに xcstrings が無いため確認できず、代わりにビルドした App の en.lproj に状態語 6 つの英訳があることを確認した。
- 目視していないもの: 実際の 120 秒の無応答、金額の無い使用量の行（Codex）、英語の状態語、End キーと「↓ 最新へ」の実操作。いずれも実エージェントを動かす必要がある（課金）ため行っていない。VoiceOver の実操作と XCUITest も未実施。

## P6 返答エリア・承認（05 Reply Area）

### 対応表

| 機能一覧（05 の対応表） | 区分 | 内容 | 実装箇所 |
|---|---|---|---|
| 承認バナー（command / fileChange / permissions・4 択）（R6〜R6f） | 変更 | 会話の上端から入力欄の直上へ移し、承認カードにした。見出し「承認待ち · 種類」・経過（「3 分前から」）・1 行目に何をするか・枠に対象そのもの（コマンド全文 / ファイルと増減行数 / 追加するルール）・作業ディレクトリとツール。ボタンは「許可 / このセッション中は許可 / 拒否 / キャンセル」。複数の要求は「1 / 3」と前後の送りで 1 枚ずつ。出るたびに 0.5 秒は押せず、許可ボタンの下端に進み具合を出す。Claude のツールの使用許可（can_use_tool。これまで Allow / Deny の質問カード）も同じカードにそろえた | `ChatReplyApproval.swift`（`ReplyApproval`・`ApprovalCard`）、`ChatApprovalRequest` に command / workingDirectory / permissionsText / requestedAt、`ChatToolPermission`（StructuredChatKit）、`ClaudeChatClient.makeToolPermissionQuestion` |
| 承認のキー（R6・R6b） | 変更（新設） | 入力欄にいるときはメニュー「セッション › 許可 ⌥⌘↩ / 拒否 ⌥⌘⌫」（表示中のカードに効き、0.5 秒の待ちも同じ）。入力欄で Tab（候補が出ていないとき）→ カードへ移り、Y / S / N / Esc で返す。カードで Tab → 入力欄へ戻る。カードが出てもフォーカスは動かさない | `PhloxApp.SessionCommands`、`ChatSessionViewModel.respondToCurrentApproval` / `replyCardFocusRequest`、`IMESafeTextView.onTab` |
| ユーザー質問（R7〜R7d） | 変更 | 未回答の質問は会話に流さず入力欄の直上に出す（見出し「質問待ち · 見出し」、右上に「1 つ選ぶ / 複数選べる / 秘密の入力」、選択肢に番号、下に「閉じる / 回答を送信 ⌘↩」）。カードにフォーカスがあるとき 1〜9・⌘↩・Esc。回答済み・期限切れは会話に 1 行で残す（「回答済み 見出し: 回答」「期限切れ「質問」— 回答は送られませんでした」、秘密は伏せ字） | `ChatReplyArea.questionCard`、`UserQuestionCell`（`placement`）、`ChatItemView`（未回答の質問は会話では描かない） |
| 複数行入力・プレースホルダー・高さ（R1・R2） | 既存のまま | 36〜160pt・IME 保護は従来どおり | — |
| 構文ハイライト（R2） | 既存のまま | — | — |
| IME 保護・Undo / Redo・送信・改行・⌘V | 変更（案内） | 入力欄の下にキーの案内（「↩ 送信 · ⇧↩ 改行 · ⌘Z 取り消し · ⌘V 画像も貼り付け」。承認・質問があるときはその操作のキー）。グリッドのタイルでは出さない | `ReplyKeyHints` |
| 入力履歴スクラババー（R2） | 既存のまま（未実施） | 下記「決定・食い違い」 | — |
| スラッシュ / スキル / @ ファイル候補（R3・R3b） | 変更 | 右端に出どころ（組込 / .claude/commands / .claude/skills / 実行時に受け取ったもの。Codex のスキルは .claude/skills と同じ「スキル」）。5 秒キャッシュ・キー操作は従来どおり | `SuggestionCandidate.origin`、`SlashCommandOrigin`、`ComposerSuggestionPopup.originLabel` |
| 画像貼り付け・添付・上限（R8・案 A〜C） | 既存のまま | 案 A〜C は未確定のため従来どおり | — |
| エージェント別コントロール（O1〜O6） | 変更（一部） | 権限の表示を「権限: 標準」の形にした（「承認設定」を出さない）。モデル・effort・推論の深さのメニューは従来どおり | `ComposerSettingsControlsView.permissionChipTitle` |
| モデル一覧の CLI 取得失敗（O3） | 変更 | 内蔵の一覧を出しているときは、モデルのメニューの下に「CLI からモデル一覧を取得できませんでした。内蔵の一覧を表示しています。」と「再試行」 | `ChatSessionViewModel.isUsingBuiltinModelList` / `retryModelListFetch` |
| ブランチ表示・切り替え・失敗（O7） | 既存のまま | 切り替えの失敗は従来どおりアラート | — |
| コンテキスト使用率（O8） | 変更 | 円の横に「46%」。80% 以上で /compact の案内をポップオーバーに足した（Cursor は /compact を持たないので出さない） | `ComposerContextIndicator`（`suggestsCompact`） |
| 送信 / 中断（R4・R5） | 変更 | 右端の丸ボタン 1 つにした。送信中は「…」で押せず、送った本文を入力欄に淡く残す。実行中で入力が空なら ■（中断）、本文があれば送信（実行中の追加の指示をボタンからも送れるように） | `ChatComposerFooter.sendOrStopButton`、`ComposerRoundButton`、`ChatSessionViewModel.inFlightText` |
| 送信失敗時の下書き復元（R9） | 変更 | 入力欄の直上に理由（1 行目だけ）と「再送」。下書きを戻せたときだけ「下書きを入力欄に戻しました」と再送を出す。送信を始めてから受け付けてもらうまで（画像の設定待ちと送信中の「…」の間）は入力欄を書けず、送り直しもできない。戻す本文と新しい下書きがぶつからないようにするため。「再送」は ↩ と同じく入力欄の本文を送る（戻した本文を書き直してから送れるように） | `ChatSessionViewModel.sendFailure` / `restoreDraftAfterRejectedSend`、`SendFailureNotice` |
| 幅による下の列の切り替え（600 / 490pt） | 変更 | 600pt 未満でブランチを隠す（グリッドはタイルの幅で判断）。490pt 未満の「設定」メニューへのまとめは従来どおり | `ChatComposerFooter.showsBranchOverride`、`GridComposerBar.showsBranch` |
| 送信滞留の診断ログ | 既存のまま | 画面には出さない | — |

### 決定・食い違い

- **承認カードへの移動は Tab だけ**。05 は「Tab か ⌘J」とするが、13 Review のキー表で ⌘J は「次の対応待ちへ」に確定しているため。
- **Claude のツール使用許可の状態は「質問待ち」のまま**（一覧・タブ・通知）。カードは承認カードにしたが、状態を「承認待ち」へ変えると状態遷移と通知の経路に広く触れるため今回は変えていない。Claude のツール使用許可には「このセッション中は許可」を出さない（ターン単位の許可しか返せない）。キャンセルは質問カードの「閉じる」と同じ（ターンを中断する）。
- **「このセッション中は許可」の説明は「このセッションが終わるまで有効です」だけ**。範囲（同じコマンドか同じ種類か）は 05 の分岐候補（未確認）なので書かない。
- **権限の変更は追加するルールだけ出す**。追加先は受け取るデータに無いため出さない。ルールは受け取った JSON を短く整形したもの（中身の形は未確認）。
- **Codex の権限はキーごとの選択（承認方式 × サンドボックス）にしていない**。凍結受け入れテスト `ComposerModeMenuAcceptanceTests` がプロフィールの一覧（:read-only / :workspace / :danger-full-access / plan）を固定しているため。Plan も従来どおりメニューの選択肢（トグルにしていない）。
- **Cursor のモデルの検索欄は入れていない**（メニューに文字入力を置けないため。ポップオーバーへの作り替えが要る）。
- **入力履歴スクラババーは会話の左端のまま**。入力欄の右上への移動と「クリックで呼び戻す」（入力中の下書きを上書きする）は、動きの変更が大きく、発言へ移動する現行の機能を失うため今回は見送った。↑ での呼び出しも未確認のため入れていない。
- **ブランチの切り替えの失敗は従来どおりアラート**（05 はポップオーバーの中に出す）。凍結受け入れテスト `AcceptanceBranchPickerPresentationTests` がポップオーバーの状態を固定している。
- **入力欄の上の宛先の行（「プロジェクト / セッション — 送信不可…」）は残した**。05 のモックには無いが既存の機能。英語表示でも日本語のまま出る（従来から）。
- `UIWording.acceptAction`（「承認」）と `approvalLabel` / `permissionLabel`（「承認設定」）は画面から使わなくなった。値は凍結受け入れテスト `AcceptanceUIWordingTests` が固定しているので残した。新しい文言は `Localizable.xcstrings`。
- 承認待ちの間も入力欄から送信できる（従来どおり）。05 の「送信は承認のあと」は未確認のため変えていない。
- 変更前から同じ経路の既存挙動として今回は直していないもの: Claude の許可返答の送信に失敗しても画面は回答済みになる／送信失敗のあとに再送すると同じ発言が会話に 2 行残る。

### テストの更新

- 凍結テストは変更していない。
- 新設 `DashboardFeatureTests/ReplyAreaApprovalTests.swift`: Claude のツール使用許可が承認カードになり質問カードに出ない、0.5 秒以内の押下を無視して以後は Allow を返す、画面に出ていない要求はメニューのキーでも返せない、増減行数の数え方、送信失敗の理由・下書きの復元・再送、送信中は送り直せず失敗した本文が戻る。

### 検証

- `.claude/verify.sh`（DesignSystem・AgentDomain・SessionFeature・DashboardFeature・App の Debug ビルド）合格。StructuredChatKit 26・ClaudeAgentKit 164・AppBootstrap 161・ControlServer 158・TerminalUI 79 が合格（`--no-parallel`）。`git diff --check` 問題なし。AppBootstrap はビルドキャッシュのため `swift package clean` の後に実行。
- Codex（gpt-6-sol high）の独立レビュー: 高 2・中 5・低 1。0.5 秒の待ちをページを戻したときにもやり直す・MultiEdit のパス・グリッドの幅でのブランチ・Codex スキルの出どころ・1 行表示・下書きを戻せなかったときの通知・送信待ちの入力、を修正。残り 2 件は上の既存挙動。再レビューで未解消 2 件（送信待ちに書いた下書きで復元が効かない・グリッドの判定が提案幅）と新しい指摘 1 件（戻した本文と新しい下書きを並べると再送で両方送る）が出たため、送信中は入力欄を書けなくし、判定をタイルの幅に改めた。3 回目の確認で残った画像の設定待ちの隙間と送信中の Enter による二重送信も、送信の開始時点から書けなくすることで塞いだ。再送が書き直した本文を送るのは上の決定のとおり。
- テスト内の描画（PNG、ライト・ダーク）: 承認カード 3 種（コマンド「1 / 3」・ファイル 2 件と増減・権限）・質問カード・回答済み / 期限切れの 1 行・キーの案内。質問カードの文字の大きさをモックに合わせて直した。
- Debug 版での目視（スクリーンショット）: ライト＋英語で入力欄の下のキーの案内・丸い送信ボタン・「Permissions: Not configured」。ダークで Claude の会話の入力欄（「権限: 自動判定」・モデル・effort・案内）。メニュー「セッション」に「許可」「拒否」があることを AX で確認。
- 目視していないもの: 実際の承認・質問の到着と、そのときの Tab・Y/S/N・1〜9・⌥⌘↩ の実操作、送信中の「…」、送信失敗の通知、Cursor の内蔵一覧の案内、80% の案内（いずれも実エージェントを動かす必要がある＝課金のため）。VoiceOver の実操作と XCUITest も未実施。

## P7 グリッド（06 Grid）

### 対応表

| 機能一覧（06 の対応表） | 区分 | 内容 | 実装箇所 |
|---|---|---|---|
| 分割ツリーによるタイル配置（S1〜S3b） | 変更 | タイルを大・中・小に分けた（小＝幅 250pt 未満か高さ 175pt 未満、大＝幅 480pt 以上かつ高さ 330pt 以上、残りが中）。大と、中で高さ 300pt 以上は会話の列（入力欄つき）。それ以外は最後の発言と、いま求められていること（承認・質問・エラー・無応答・実行中）だけ。文字は縮めない | `GridTileParts.swift`（`GridTileSize`・`GridTileCompactBody`）、`PaneLayoutView.PaneTileView` |
| タイル見出し | 変更 | 左から状態の文字（「承認待ち · 3分」「無応答 2:14」。対応待ちは状態の色・太字、実行中は太字、他は弱い文字）・内部タグ・タイトル・未読の点・幅 380pt 以上で「会話 / 端末 / 変更」・エージェント略称・⌘番号・✕。小ではエージェント略称と番号を隠す | `GridTileHeader`、`GridTileText` |
| レイアウトプリセット 9 種 | 変更 | 表示範囲バーの右端「レイアウト: バランス ▾」。名前をモックに合わせた。手で崩したら「（調整済み）」、プリセットを選び直すと外れる。選んだプリセットと調整済みかどうかを保存。メニュー「表示 › グリッドのレイアウト」からも選べる | `PaneLayoutPresetMenu`、`PaneLayoutPresets.displayName`、`PaneLayoutStore.PresetState`、`DashboardViewModel.paneLayoutPresetState`、`PhloxApp.ViewCommands` |
| タイルのドラッグ（入れ替え / 分割挿入）・ドロップ先のハイライト（S8） | 変更 | ハイライトにアクセントの縁と結果の文字（「入れ替え」「右に分割して挿入」など）、分割挿入では差し込む線。ドラッグ中は凡例（中央＝入れ替え・端＝分割）を出す | `PaneDropIndicatorView`、`PaneDropLegend` |
| 分割線のドラッグ・等分・ホバー・当たり 8pt（S9） | 変更 | ゴーストに「⟷ 62% · 718pt ／ 最小 240 × 160pt ／ ダブルクリックで等分」。確定は従来どおりマウスアップで 1 回 | `PaneDividerHandleView.ghostLabel` |
| タイルクリックでフォーカス・見出しの mouseDown で即時選択 | 変更 | フォーカスは状態の色と別の、アクセントの外輪（2pt）。状態の色は内側の縁 | `PaneTileView` |
| タイルの右クリック | 変更 | 「グリッドから外す」を先頭に足した（名前を変更 / プロジェクトを変更（PTY のみ）/ 削除は従来どおり） | `PaneTileView.contextMenu` |
| タイルを閉じる（×）・⌘W | 変更 | ✕ と ⌘W は「グリッドから外す」（セッションは消さない。表示セッションの選択から外す）。外したら次のタイルへフォーカスを移す。メニューの ⌘W の名前もグリッドでは「グリッドから外す」 | `DashboardViewModel.removeFromGrid`、`SessionTabs.CloseCommandTarget.gridTile`、`TabRequest.removeFromGrid` |
| ⌘1–9 | 変更 | タイルを左上から数えた順（行の上から、同じ行は左から）。見出しの ⌘ 番号と同じ並び | `PaneTree.readingOrder()`、`DashboardViewModel.gridTileOrder` |
| 幅 240pt 未満でのヘッダの縮退 | 変更（統合） | 小サイズの規則に統合 | `GridTileSize` |
| 要注意 / 停止のハイライト（S5） | 変更 | 対応待ちの 4 状態だけ見出しを状態の色で塗り、内側の縁も同じ色 | `GridTileHeader`、`PaneTileView`（`GridTileBorderPolicy`） |
| タイル本文（PTY・チャット・承認・子タブ） | 変更 | 承認カードは「許可 / このセッション中は許可 / 拒否」（小は「許可 / 開く」）。フォーカスしていないタイルでも直接押せ、出てから 0.5 秒は押せない。質問は「開いて回答」、エラーは「開く」、無応答は「中断」。子タブの「端末」はそのセッションの端末、「変更」はフォーカス中のタイルだけ中身を出す | `GridTileApprovalCard`、`DashboardView.gridTileTabs` |
| タイル内の送信 / 中断・候補・強調・Esc・サブエージェント | 既存のまま（大・中の高いタイル）／変更（それ以外） | 会話の列を出すタイルは返答エリアと同じ。出さないタイルは「開く」「開いて回答」で単体表示へ移って入力する（「クリックで大きくして入力」） | `GridChatColumn`（従来）、`GridTileCompactBody` |
| ライブリサイズ中のレイアウト凍結 | 既存のまま | — | — |
| オーケストレーションの子セッション（S7） | 変更 | 見出しに「内部」、本文の上に「↳ 親: 親の名前」 | `GridTileParentRow`、`DashboardDetailView.parentNames` |
| プロジェクト絞り込み・表示セッション選択・各解除・サマリ（S6） | 変更 | 「表示範囲 ［すべてのプロジェクト / プロジェクト名 ✕］［3 / 4 件を表示 ✕ ▾］」。2 つの ✕ は別々に効く。範囲外の対応待ちを「エラー 1 無応答 1 が範囲外 ›」（状態ごとの色・件数）で出し、押すと対応待ちの一覧 | `GridModeBar`、`GridOutOfScopeAttention` |
| グリッドの空スコープ（S10） | 変更 | 「表示するセッションがありません」・理由・「絞り込みを解除」・「<プロジェクト> で新規セッション ⌘N」 | `DashboardView.gridScopeEmptyState` |

### 決定・食い違い

- **最後の 1 枚はグリッドから外せない**（✕ は押せず、⌘W は何もしない）。表示セッションの選択が空になると「すべて表示」に戻ってしまうため。
- **⌘ 番号は固定の大きさ（1600 × 1000・余白 0）で数える**。ウィンドウの大きさで最小寸法の押し戻しが効いても番号が入れ替わらないように。
- **子タブの「変更」はフォーカス中のタイルだけ中身を出す**。変更の画面は選択中のセッションに結びついているため。他のタイルでは「タイルを選ぶと変更を表示します」。
- **Claude のツール使用許可を「承認待ち」として出すようにした**（P6 の「質問待ちのまま」を改めた）。グリッドで承認カードを出すタイルの見出しが「質問待ち」になる食い違いを避けるため。`ChatSessionViewModel.displayStatus` で、未回答が使用許可だけのときに承認待ちへ写す。
- **「調整済み」は並びが実際に変わった操作だけで付ける**（何も変わらない入れ替え・分割線の操作では付けない）。プリセット名の記録が無い旧データは、保存済みの配置がバランスと完全に同じときだけ未調整とし、その結果を保存する（セッションの増減で自動に並べ直しただけの旧データも「調整済み」になり得る）。
- **未読の点はアクセント色**。Codex のレビューで「色は対応待ち 4 状態だけ」に反すると指摘されたが、グリッドのモック（`PhloxGrid.dc.html` の `aria-label="未読"`）が `var(--accent)` で描いている（サイドバーも同じ）。
- 06 S4 の「⌥⌘2」は 13 Review のキー表（⌘1–9＝タイル）で置き換わったので使わない。
- 子セッションのタイルはプロジェクトで絞り込んだときだけ出る（従来どおり）。
- ツールバーから開くポップオーバー（対応待ちの一覧・表示セッションの選択）はアプリ内の言語設定を受け継がず、英語表示でも日本語になっていた。言語を渡し直して直した。「単体 / グリッド」の切り替えの文言も同じく直した。
- 入れていないもの: S8 の「元のタイルを薄く残す」（`.draggable` にドラッグ開始の通知が無い）、⌥⇧⌘＋矢印のタイル入れ替えと ⌃⌥＋矢印の分割線移動（モックで「案」）。
- 英語表示でも日本語のまま残るもの（従来から）: メニューバー、入力欄の上の宛先の行、使用量の「残り」。

### テストの更新

- 凍結テストは変更していない。
- `SessionTabsTests.closeTargetsSession`（P3 で自分が足したテスト）: グリッドの ⌘W の対象を `.gridTile` に改めた。
- 新設 `DashboardFeatureTests/GridTileRedesignTests.swift`: タイルの大きさの境界、見出しの状態の文字、読み上げの順、⌘ 番号の並びと入れ替え後、グリッドから外す（最後の 1 枚と表示外）、調整済みの付け外しと保存、記録の無い旧データの判定、範囲外の対応待ちの件数と順、グリッドの ⌘W。

### 検証

- `.claude/verify.sh`（DesignSystem・AgentDomain・SessionFeature・DashboardFeature・App の Debug ビルド）合格。SessionFeature 1051・StructuredChatKit 26・ClaudeAgentKit 164・AppBootstrap 161・ControlServer 158・TerminalUI 79 が合格（`--no-parallel`）。ControlServer は 2 回目の実行で `AcceptanceSpawnProjectIdTests` の 1 件が HTTP のタイムアウトで失敗し、単独の再実行で合格。`git diff --check` 問題なし。
- Codex（gpt-6-sol high）の独立レビュー: 中 4・低 1。旧データのレイアウト名・表示範囲のヘルプ文の言語・⌘ 番号と見出しの番号のずれを修正。最後の 1 枚と未読の点は上の決定のとおり。メニューの言語は従来からの制約。
- Debug 版での目視（スクリーンショット）: ライト＋日本語で表示範囲バー・エラーのタイル（見出しの色・縁・カード・「開く」）・子タブと ⌘ 番号・フォーカスの外輪・⌘W で外して次のタイルへ移る・✕ で戻す・右クリックのメニュー・分割線のゴースト・見出しのドラッグでの入れ替えと凡例・「バランス（調整済み）」・プロジェクト絞り込み（「CapWeave ✕」「2 / 2 件（すべて）」「エラー 2 が範囲外 ›」）・S10。ダーク＋英語で表示範囲バー・タイル見出し・子タブ・対応待ちの一覧・表示セッションの選択。
- 目視していないもの: 実際の承認・質問・無応答のタイル（テスト内の描画だけ）、内部タグと親の行、子タブの端末・変更の中身（実エージェントを動かす必要がある＝課金のため）。VoiceOver の実操作と XCUITest も未実施。

## P8 インスペクタとツール（07 Inspector and Tools）

### 対応表

| 機能一覧（07 の対応表） | 区分 | 内容 | 実装箇所 |
|---|---|---|---|
| セッションのメタ情報（I1・I2） | 変更 | インスペクタの上に「セッション / 使用量」の切り替え。「セッション」は見出し（タイトルと「エージェント · チャット型 / ターミナル型 · プロジェクト · 短い ID」）と、状態・経過時間・総コスト・ブランチ・プロジェクト・作業ディレクトリの行。ターミナル型でも出し、取れない値（コスト）は「—」と注記 | `InspectorView`、`SessionInfoPanel`、`AppRouter.inspectorTab` |
| CLI 使用量カード（U1・U3・U5） | 変更 | CLI ごとのカードに全バケットの「残り N%」・ゲージ・「N 時間 M 分後にリセット」。残り 20% 未満は琥珀＋太字、リセットに「· 上限間近」、カードの縁も琥珀。Claude は取得時刻の注記（古くなったら既存の鮮度注記を琥珀で） | `UsageSidebarView`（`UsageCLICard`・`UsageBucketRow`・`UsageText`） |
| 取得失敗・読込中（U2・U4） | 変更 | 初回の取得中だけ骨組み（「取得中…」）。2 回目以降は値を残し、更新ボタンを回すだけ。取得に失敗して前回の値を出している CLI は注記「N 前の値」を琥珀にし、数字とゲージを淡くする。全部が失敗なら上に「使用量を更新できませんでした」と理由・時刻・何分前の値か | `UsageMonitor.failures` / `lastSucceededAt` |
| Cursor 未インストール時の誘導（U6） | 変更（見た目） | 理由の文と「Cursor をインストールしに行く ↗」。「未取得の CLI も表示」がオンのときだけ（従来どおり） | `UsageCLICard` |
| 使用量の手動更新 | 変更 | 下端に「最終更新 14:32 · 自動更新 オン」（失敗時は「（失敗 14:32）」）と「更新 / 更新中 / 再試行」。その下に設定の置き場所の案内 | `UsageSidebarView.footer` |
| 使用量チップ（上部バー） | 変更 | エージェントごとに一番少ないバケットの残量を 1 つ（「Claude ▬ 38%」）。20% 未満は琥珀＋太字、取得失敗は「—」、更新中は淡く。押すとインスペクタの「使用量」を開く。狭い幅ではゲージを外し、さらに最小の 1 つだけにする（従来の縮退） | `UsageTopBarView`、`AppRouter.showUsageInInspector` |
| エディタのレイアウト自動切替（541pt） | 既存のまま | — | `EditorPanelLayout` |
| 変更ファイル一覧・種別・バイナリ | 変更 | 種別を文字（M / A / R / D / U、バイナリは B）で示し、追加は緑・削除は赤・ほかは無彩色（従来は変更に承認待ちの色を使っていた）。行はファイル名とフォルダの 2 行 | `editorChangeLetter` / `editorChangeColor`、`EditorPanelView.changeFileRow` |
| 差分 / 内容・500 行ごとの「さらに表示」 | 変更 | 差分のとき、中身を読めていれば上端の「差分 / 内容」で切り替える（ファイルを選び直すと差分に戻る）。差分の行は追加を緑・削除を赤で塗る。「さらに表示（残り N 行）」 | `EditorPanelView.detailPreview` / `diffHighlight` |
| コミット対象のチェック | 変更 | コミットボタンに件数「コミット（3）」 | `GitCommitPanel.commitButton` |
| Git 処理状態・詳細ログ・閉じる（D5） | 変更 | 詳細ログを 84pt で畳み、「ログをすべて表示」かログのクリックで広げる。状態は 1 行 | `GitCommitPanel` |
| ファイル編集・保存・競合（D4）・共有スコープ注意（D6）・コミット / プッシュ / PR | 既存のまま | 競合相手のセッション名は出さない（07 の分岐候補） | — |
| ターミナル: シェル・PTY 維持・起動・失敗の行（D1・D7） | 変更（見出し） | 見出しに「ターミナル  zsh · ~/dev/phlox」。グリッドのタイルでは出さない | `TerminalPanelView` |
| 文字サイズ（D8） | 変更（新設） | 見出しの「A− 13pt A+」（⌘− / ⌘+ と同じ経路）。大きさが変わると中央に「ターミナル 14pt」を 1 秒。子タブ・共通ターミナルにも変更がすぐ効くようにした（従来はエージェントの端末だけに効いていた） | `TerminalPanelView`、`EnvironmentValues.adjustTerminalFontSize` |
| ドロワーの開閉・積み方・幅 | 廃止済み | 07 の更新で子タブへ移った（P3） | — |
| TerminalUI の各機能 | 既存のまま | — | — |

### 決定・食い違い

- **「状態」はセッションの行に置いた**（07 と補助領域のモックのとおり）。13 Review の「状態は見出しのカードで表示」は骨格の話と読んだ。
- **シェル再起動のボタンは入れていない**（07 の分岐候補）。見出しの ✕ も子タブの ✕ があるので置いていない。
- **Claude の鮮度注記の文言は既存のまま**（「30分前の値」など）。モックの「43 分前に取得 · 古い可能性」とは違うが、凍結受け入れテスト `ClaudeUsageVisibilityAcceptanceTests` が固定している。
- **取得失敗の記録は前回の値を出している間だけ**。前回の値は 5 分で捨てる従来の契約（`UsageMonitor.resolvedUsage` と既存テスト）を変えていないので、障害が続くとカードは理由の表示に変わる。初回から取れないときはバナーを出さず、カードの理由と「再試行」だけ。
- **全部が失敗のときだけバナー**。1 つだけならその CLI の注記を琥珀にする。
- **チップの残量は全バケットの最小**。取得失敗の CLI は「—」。
- **カードの頭はブランドのアイコン**（モックは「Cl」などの文字）。上部バー以外の既存の見た目にそろえた。
- **切り替え（セッション / 使用量、差分 / 内容）は無彩色の部品を新設した**（システムの segmented はアクセント色で塗るため）。
- `editorChangeIcon`（SF Symbol）は画面から使わなくなったが、凍結テスト `EditorPanelIconWhiteboxTests` が固定しているので残した。
- 英語表示でも日本語のまま残るもの（従来から）: 提供元が返す取得失敗の理由・Claude の鮮度注記・チップのヘルプ文（`topBarHelpText` は凍結テストが日本語を固定）・プッシュ / PR の不可理由。

### テストの更新

- 凍結テストは変更していない。`GitWorkflowWhiteboxTests` の「畳んだ状態表示は 120pt 未満」に合わせ、状態を 1 行にしてログを開くボタンを同じ行に置いた。
- 新設 `DashboardFeatureTests/InspectorRedesignTests.swift`: 取得失敗を前回の値の間だけ記録し成功で消す、前回の値が無い失敗は記録しない、チップから「使用量」を開く、種別の文字、リセットまでの文言。

### 検証

- `.claude/verify.sh` 合格。SessionFeature 1051・AppBootstrap 161・ControlServer 158・StructuredChatKit 26・ClaudeAgentKit 164・TerminalUI 79 が合格（`--no-parallel`）。ControlServer は初回に `AcceptanceSpawnProjectIdTests` の 1 件が HTTP のタイムアウトで失敗し、再実行で合格。`git diff --check` 問題なし。Codex の指摘の修正後に DashboardFeature の関連 133 件を再実行して合格。
- Codex（gpt-6-sol high）の独立レビュー: 高 3・中 4。失敗時のチップの「—」・全バケットの最小・全件失敗の判定・初回失敗の「再試行」・ログの開閉をキーで押せるボタンに、を修正。取得理由などの言語と 5 分で前回の値を捨てる点は上の決定のとおり。
- Debug 版での目視（スクリーンショット）: ライト＋日本語でチップ・使用量タブ・セッションタブ・共通ターミナルの見出し・A+ で「ターミナル 14pt」が出て 1 秒で消える・変更タブ（種別の文字・差分）。ダーク＋英語でチップ・使用量タブ・変更タブ（差分の色・「Commit (1)」・内容・「Show More (276 lines left)」）。
- 目視していないもの: 取得失敗のバナーと琥珀の注記（ネットワークを切る必要がある。テストで記録のみ確認）、初回の骨組み、ターミナル型セッションのセッションタブ、Git の失敗ログ。VoiceOver の実操作と XCUITest も未実施。

## P9 空の画面と新規セッション（08 Start and New Session）

### 対応表

| 機能一覧（08 の対応表・9 章・10 章） | 区分 | 内容 | 実装箇所 |
|---|---|---|---|
| プロジェクト 0 件のフォルダ追加（S1） | 変更 | 「Phlox へようこそ」と手順 1 フォルダ（⌘O）・2 使えるエージェント（PATH の検出結果とパス、未検出も出す）・3 通知（許可の状態に応じて「通知を許可…」「許可済み」「システム設定を開く…」）。一度でもプロジェクトを持ったら手順 1 だけ | `StartOnboardingView`、`DashboardView.hasAddedProject` |
| プロジェクト未選択のプレースホルダ（S2） | 変更 | 補足「左のサイドバーでプロジェクトかセッションを選ぶと…⌘J で移動できます」 | `SelectProjectPlaceholderView` |
| 起動カード群・起動中の無効化・構造化チャット対応による出し分け（S3〜S5） | 変更 | 上にプロジェクトの見出し（名前・パス・ブランチ・worktree 隔離・実行中の件数）。カードに番号・実行ファイルのパス・モデル（この種別で最後に使ったもの）・権限の初期値。未検出の種別もカスタムも元の位置に淡く残し理由を出す。チャット非対応はターミナルを主ボタンに。起動中はそのカードに「起動しています…」、ほかは淡く | `AgentStartCardsView`（`entries` / `creatingRef` / `header`）、`AgentStartEntries`、`DashboardViewModel.agentStartEntries` |
| カード列の横並び ⇄ 折り返し（S5） | 変更 | 縦積みへの切替は凍結済みの `AgentStartCardsLayoutPolicy` のまま。横並びのときは 1 枚 200pt を目安に最大 4 列で折り返す（同じ行の高さはそろえる） | `AgentStartCardsView.columnCount` |
| カードのキー操作 | 変更（新設） | カード領域にフォーカスしたとき 1–N と矢印で選び、↩ で既定の開き方・⌥↩ でもう一方 | `AgentStartCardsView`、`NewSessionKeys` |
| 新規セッションの入口（メニュー・サイドバーの ＋ / 下端・グリッドの空状態） | 変更 | ⌘N / ⇧⌘N / ⌥⌘N を「新規セッション…」⌘N 1 つにまとめ、種別 × 開き方の表を開く（サイドバーが出ていれば下端から）。表は `NewSessionMenuModel` から組み、見出しで作成先を変えられる（選択中のプロジェクトもセッションも無く、プロジェクトが 2 つ以上なら未選択で、選ぶまで押せない）。未検出の種別は「未検出」で選べない行にする。起動中はボタンを押せない。1–N / ↑↓ / ↩ / ⌥↩、下端に既定の開き方。右クリックの「新規セッション」は従来のメニューのまま | `NewSessionTable`、`NewSessionPopoverButton`、`AppRouter.newSessionTablePresented`、`SessionCommands` |
| 作業ディレクトリの衝突（F1・WorkspaceCollisionPolicy） | 変更（新設） | 隔離オフのプロジェクトで、同じフォルダに動いているセッションがあれば起動前にたずねる。相手を状態付きで並べ、既定は「worktree で分けて起動」 | `NewSessionCollisionGate`、`SpawnGuardSheet`、`DashboardView.createSession` |
| worktree の作成（F2） | 変更 | 作っている間、下端に「worktree を作成しています…」 | `DashboardView.worktreeProgressToast` |
| worktree の作成失敗（F4） | 変更 | 起動を中止した旨と git の出力（無ければ理由の文）、「worktree なしで起動」 | `SpawnGuardSheet`、`NewSessionCollisionGate.worktreeFailureLog` |
| この起動だけの隔離の有無 | 変更（新設） | F1・F4 の選択をプロジェクトの設定を変えずにこの起動だけに渡す。「worktree なしで起動」はセッションの保存情報に残し、復元でも worktree を作らない | `spawnNewSession(… isolationOverride:)` → `SessionSpawnService.prepareSessionLaunchAsync`、`PersistedSessionDescriptor.worktreeIsolationOptOut`、`SessionRestoreCoordinator` |
| 起動の失敗（F5・深さ / レート上限・CLI 未検出など） | 変更（経路） | メニューからの作成も画面の作成処理を通すので、失敗が既存のアラートに出る（従来は `try?` で黙って消えていた） | `DashboardView.createSession` |
| worktree の作り直し（F3） | 据え置き | 復元時は従来どおり確認なしで作り直す | — |
| Control API・CLI からの作成 | 既存のまま | 確認を出さずに作る（衝突の確認は画面の作成処理だけ） | — |

### 決定・食い違い

- **手順 1 の見出しは「プロジェクトを追加してください」**（モックは「プロジェクトを追加」）。凍結 UI テストがこの文言（英語 "Add a project"）を探す。
- **カードの列は凍結ポリシー優先**。08 の「900pt 以上で 4 列・未満で 2 列」ではなく、縦積みの判定は `AgentStartCardsLayoutPolicy`（700pt で 3 枚は横並び）を守り、横並びの中だけ折り返す。
- **「再検出」「入手方法 ↗」は出さない**。CLI のパスは起動時に 1 回だけ解決していて再検出の仕組みが無く、入手先の URL も持っていない。未検出の理由の文は「インストールしてアプリを開き直すと、ここから起動できます」にした。
- **バージョンは出さずパスだけ**（バージョンを取る仕組みが無い）。
- **権限の初期値はアプリが起動時に決めているものだけ**: Codex は常に（承認方針 · サンドボックス）、Claude Code と Cursor はフルアクセスのときだけ。それ以外とカスタムは「（CLI の既定）」。モデルは最後に使ったもの（チャット対応の種別だけ）。
- **↩ は既定の開き方**（モックは「↩ チャット」固定）。ADR 0071 の「GUI からの作成は既定の開き方に従う」を守った。案内の文言も設定に合わせて入れ替わる。
- **F1 は画面の作成処理だけで出す**。VM の `spawnNewSession` には入れず、Control API と既存テスト（同じフォルダの複数セッションを許す）の「確認なしで作成」を保った。「worktree で分けて起動」を選ぶと、git でないフォルダでは F4 になる。
- **F4 の「既存の worktree を使う」は出さない**。新規セッションの worktree はセッション ID ごとに新しく作るので、既存のものを使う経路が無い。
- **F2 のパスは出さない**。worktree の場所は起動の中でセッション ID が決まってから分かる。
- **「worktree なしで起動」は保存して復元に引き継ぐ**。復元は隔離オンのプロジェクトでは必ず worktree を使うか中止する（凍結受け入れテスト `AcceptanceRestoreAbortNoSpawnTests`）ため、記録なしでは再起動で新しい worktree へ移ってしまう。セッションの保存情報に任意の項目 `worktreeIsolationOptOut` を足し、記録があるときだけ復元でも隔離しない（旧データはキーが無いので従来どおり）。
- **表を開いたときは表にキー入力を向ける**（Codex の低の指摘は取らない）。ユーザーが ⌘N や ＋ で開いた表で 1–N / ↩ を使うためで、作業中の入力欄から勝手に奪う動きではない。閉じると元に戻る。
- **F3 は据え置き**。作り直しは復元のときだけ起き、確認を挟むには復元の流れに割り込みが要る。
- 英語表示でも日本語のまま残るもの（従来から）: worktree の失敗理由の文（`WorktreeIsolationSpawnError` の文言）、メニューバーの項目。

### テストの更新

- 凍結テストは変更していない。`AgentStartCardsView` の既存 init・`AgentStartCard(kind:)`・`cards(available:)`・レイアウト定数を保ち、カードの外形の最小幅（148 + 左右 12）も合わせた。
- 新設 `DashboardFeatureTests/StartScreenRedesignTests.swift`: 未検出も並びどおり残す・権限の初期値・モデルの文言・表の行・↩ / ⌥↩ と既定の開き方・衝突の相手（隔離オンなら無し、終了済み・別フォルダは除く）・worktree の失敗の出し方。
- `WorktreeIsolationSpawnTests` に 2 件追加: 隔離オフのプロジェクトでもこの起動だけ worktree を作り設定は変えない、隔離オンの git でないフォルダでもこの起動だけ共有フォルダで動かす。override で作った worktree の復元は既存の `restoreTracksExistingWorktreeAfterIsolationIsDisabled` が扱う。

### 検証

- `.claude/verify.sh` 合格。MessageStore 40・ControlServer 158・AppBootstrap 161 が合格（`--no-parallel`）。`git diff --check` 問題なし。新設・関連の DashboardFeature テスト（StartScreenRedesign・WorktreeIsolationSpawn・AcceptanceRestoreAbort・永続化まわり 111 件）合格。
- 実機 UI テストは、はじめ `IsolatedLaunchOptionsTests`・`ViewModeAccessibilityTests` の 6 件中 5 件が起動前のチェックで失敗した（「専用 suite の期待値 420.0→560.0・移行済み true が保存されない」）。起動補助 `IsolatedPhloxApplication` が設定の隔離を確かめる目印にパネル幅の移行（`phlox.panelDrawer.width.migratedTo560`）を使っていたが、その処理は P3 のタブ再設計（acc1abb）でパネルごと無くなっていた。目印を、起動時に必ず保存されるグリッド配置の記録（`phlox.grid.paneLayoutPreset`）に差し替えた（専用 suite に書かれ、通常の保存先が変わらないことを確かめる点は同じ）。`PanelUITests` が渡していた幅の引数（700→700）も外した。続けて `testSeededCustomSessionAppears` が読み上げ「起動補助確認, 入力待ち」を探して失敗したので、P1 で要件どおり「待機」に変えた語に期待値を合わせた（エラーでなく正常に待機していることを確かめる点は同じ）。修正後、`PhloxUITests` スキームの全 15 件が合格。
- Codex（gpt-6-sol high）の独立レビュー: 高 1・中 3・低 1。「worktree なしで起動」の復元・⌘N の表に未検出の種別を出す・起動中は表を押せない・未選択で先頭プロジェクトに作らない、を修正。フォーカスの指摘は上の決定のとおり。
- Debug 版での目視（スクリーンショット。課金の無い /bin/cat のカスタム種別と、別のデータフォルダ・defaults で確認）: ライト＋日本語で S1（初回・2 回目以降）・起動カード（未検出とカスタムを含む 5 枚の折り返し）・F1（同じフォルダの確認）→「worktree で分けて起動」で worktree ができて起動・S5（起動中のカードと他の減光・「worktree を作成しています…」）・git でないフォルダで F4 →「worktree なしで起動」で共有フォルダに起動・⌘N の表（数字キーで行の選択、未選択時は押せない、未検出の行）。ダーク＋英語で S1・起動カード・F1・⌘N の表。ダーク＋日本語で S2 と表の未検出の行。ライトでサイドバーを隠したときの ⌘N（上端から開く）。
- 目視していないもの: F5（深さ・レート上限の失敗。既存のアラートのまま、メニュー経由も同じ経路になったことはコードで確認）、通知の「通知を許可…」「システム設定を開く…」の状態（この Mac では許可済み）、サイドバーのプロジェクト行 ＋ とグリッドの空状態から開く表、VoiceOver の実操作。
- プロジェクトが 0 件のときは、下端の「新規セッション」もメニューの ⌘N と同じく押せなくした（表が開いても作成先を選べないため）。

## P10 確認ダイアログとアラート（09 Dialogs）

### 対応表

| 見本 | 型 | 内容 | 実装箇所 |
|---|---|---|---|
| D1 起動失敗 | C | 見出し「%@ を起動できませんでした」＋原因の文。実行ファイルが見つからないときだけ 2 つ目のボタン「エージェント管理を開く」。OK が既定 | `SpawnFailureDialogText`、`DashboardView` の `spawnError` |
| D2 後始末の失敗 | C | 「セッションは終了しています。」から書き、残った場所（worktree のパス / ブランチ名）を出す。worktree なら「Finder で表示」 | `CleanupWarningDialogText` |
| D3 セッション削除 | A | 見出しに名前と子セッションの件数。本文で停止・元に戻せないことを書き、子セッションを「名前 · 状態」で最大 6 件並べる（超えた分は件数）。未保存ファイルは子の分も含める。末尾に「プロジェクトのフォルダとファイルは削除されません。」 | `SessionDeletionDialogText`、`DashboardViewModel.descendantNodes(of:)` |
| D4 プロジェクト削除 | A | 固定の文言（`ProjectDeletionDialogText`）に、消えるセッションの件数と「元に戻せません」を足す。キャンセルを既定に | `ProjectDeletionDialogText.title/message(…locale:)`・`irreversibleNote` |
| D5 フォルダ変更 / 移動 | A | 本文を「元に戻せません」で終える | `DashboardView.shellWithTabDialogs` |
| D6 / D7 名前変更 | — | サイドバーの行の中の編集は P4 で済み（D7 の「フォルダ名は変わりません」も表示済み）。グリッドのタイルとサイドバーを隠したときの名前変更アラートは残し、「変更」を既定に | `renameSessionAlert` |
| D8 スキル削除 | B | 見出し「スキル「name」をゴミ箱に入れますか?」、本文に移す場所と「ゴミ箱から戻せます」。「ゴミ箱に入れる」を既定（赤くしない） | `ClaudeSkillsPane` |
| D9 書き出しの前段 | B | ヘッダの書き出しボタンは P5 の選択肢（推論・コマンド出力・タイムスタンプ）のまま。メニューの ⇧⌘E は前段が無かったので、保存パネルに同じ 3 つのチェックを添え、同じ保存値に書く | `ChatTranscriptExportAction.save(…showsOptions:)`、`ExportOptionsAccessory` |
| D10 書き込み失敗 | C | 「会話を書き出せませんでした」、エラー文を等幅で、2 つ目のボタン「別の場所に保存…」で保存パネルを開き直す | `ChatTranscriptExportAction.save` |
| E1 保存競合 | A | 見出しにファイル名、本文を「元に戻せません」で終える | `SessionTabsContainer.FileTabView` |
| E3 作業ディレクトリの衝突 | B | ラジオをやめ、縦に「worktree で分けて起動」（既定）・「同じディレクトリで起動」・「キャンセル」。アプリアイコン | `SpawnGuardSheet` |
| E4 worktree の作成失敗 | C | 「閉じる」を既定、「隔離なしで起動」。アプリアイコンに注意バッジ | `SpawnGuardSheet` |
| E2 worktree の作り直し | — | 据え置き（P9 の F3 と同じ） | — |

A・C 型は `.dialogSeverity(.critical)`（注意アイコン）、破壊的なボタンに ⌘⌫。子タブを閉じる確認（見本外）も同じ規則にそろえた。見出しは `String` で渡すと訳されないため、`AppLocalizedString` を通す。

### 決定・食い違い

- **A 型のダイアログは Esc で閉じない**（P10 前から同じ）。SwiftUI では 1 つのボタンに ↩ と Esc を両方割り当てられず、キャンセルに ↩（09 の指定）を付けると Esc が外れる。↩ を外すと Esc は効くが既定のボタンが無くなることを実機で確かめ、09 の指定を優先した。B 型（D8・E3）は Esc で閉じる。
- **D4 の見出し・本文は固定のまま**（凍結テスト）。モックの「プロジェクト「名前」を…」「フォルダ「パス」…」にはせず、件数と「元に戻せません」を後ろに足した。日本語表示では固定の文言と一字一句同じになることをテストで確かめている。
- **D3 は子セッションの一覧を本文の文字で並べる**（システムのダイアログに表を入れられないため）。本文の最後は見本と同じく「フォルダとファイルは削除されません」（Codex の「元に戻せません で終える」の指摘は、見本の並びを優先して取らない）。
- **D2 のエラー原文は出せない**。後始末の警告は原因の文を持っていないため、残った場所だけを出す。「未コミットの変更があるため」とは断定しない。
- **D1 の原因の文は等幅にしない**（SwiftUI のアラートの本文は書式を持てない）。原因の文（`AgentSpawnError` の文言）は従来どおり OS の言語で引いている。
- **`.dialogSeverity(.critical)` は画面の中のダイアログ全体に効く**。中にあるのは A・C 型だけ（ブランチ切替の失敗も C）で、B 型の名前変更アラートは外側に置いている。B 型を中に足すときは注意。
- D8 の確認は本物のスキルに触れないよう、テスト用フォルダに置いたダミーで確かめた。

### テストの更新

- 凍結テストは変更していない（`ProjectDeletionWarningTests`、`WorkspaceCleanupWarning` の title / message を固定する `WorktreeIsolationSpawnTests`）。
- 新設 `DashboardFeatureTests/DialogRedesignTests.swift`（5 件）: D1 の見出しと次の手の出し分け、D2 の本文・場所・Finder の有無、D3 の見出し（件数）と本文（一覧の上限・未保存ファイル・フォルダは消えない・元に戻せない）、D4 の訳付き版が固定の日本語と一致すること。

### 検証

- `.claude/verify.sh` 合格（DesignSystem・AgentDomain・SessionFeature・DashboardFeature・app build）。SessionFeature 全体 1051 件合格。`git diff --check` 問題なし。
- 実機 UI テスト（PhloxUITests）: 初回は XCTest の UI 自動化の許可（パスワード入力）待ちで起動前に失敗。許可後の全件実行で `testEnglishLightArgumentsReachApplication` だけが「専用suiteにグリッド配置の記録が保存されない」で失敗した。この記録は起動時のセッション復元が終わってから保存されるため、全体実行の最初のテスト（コールドスタート、13 秒）ではウィンドウ表示から 10 秒の待ちに間に合わなかった（同じクラスを単独で 3 回実行するとすべて合格）。P9 で目印をこの記録に差し替えたとき待ち時間を見直していなかったのが原因なので、`IsolatedPhloxApplication.assertDefaultsIsolation` の待ちをウィンドウ待ちと同じ 30 秒にした（確かめる内容は同じ）。修正後、全 15 件が合格。
- Codex（gpt-6-sol high）の独立レビュー: 高 2・中 3・低 1。D4 の件数と「元に戻せません」・子セッションの未保存ファイル・後始末の断定・書き込み失敗の OK の文言を修正。残りは上の決定のとおり。
- Debug 版での目視（スクリーンショット）: ダーク＋英語で D3（見出し・本文・既定のキャンセル・⌘⌫ で削除・↩ でキャンセル）、D4、D5（移動）、E3（Esc で閉じる）、E4。ライト＋日本語で D3、D8（↩ が既定・Esc で閉じる）。
- 目視していないもの: D1・D2・D9・D10・E1（起こすには課金のあるエージェント・書き込めない場所・外部でのファイル変更が要る。文言はテスト、ボタンはコードで確認）、子セッションのある D3 の一覧（テストで確認）、VoiceOver の実操作。

## P11 設定（10 Settings）

### 対応表

| 見本 | 内容 | 実装箇所 |
|---|---|---|
| タブ | 5 タブを 6 タブ（一般・外観・通知・エージェント・使用量・モバイル連携）に。モバイル連携はトークンがあり案内の方針が許すときだけ（現行どおり）。ウィンドウ 640×680 | `SettingsGroup.all`、`SettingsView.visibleGroups` |
| 一般 | 表示言語、新規セッションの既定の開き方（セグメント＋説明）、アップデート（自動確認・「今すぐ確認」）、バージョン（名前 版（ビルド））、プライバシーポリシーのリンク | `SettingsView` |
| 外観 | テーマをタイル（見本＋色の帯）の格子に、アプリアイコンを 48pt のタイルに。文字の大きさ: チャット本文のスライダー（80〜200%）とターミナルの入力欄＋ステッパー | `ThemeTile`・`ThemeAppPreview`・`AppIconTile`・`terminalFontRow` |
| T6b 範囲外の値 | 整数で範囲内のときだけ保存。外れたら赤い枠と「%lld〜%lld の整数を入力してください。保存していません（現在の値: %lld）」 | `TerminalFontSettings.parse`、`commitTerminalFont` |
| 通知 | バナー・完了サウンド・「通知テスト」を通知タブへ移した | `SettingsView` |
| エージェント | フルアクセスの行にオン / オフそれぞれの説明（固定の `UIWording`）、エージェント管理を開く（⇧⌘, の表示）、カスタムエージェントの定義ファイルの場所 | `BypassToggleRow` |
| 使用量 | 4 つのスイッチに見本の名前と説明 | `SettingsView` |
| モバイル連携 | 端末名、QR の表示（無効の理由を下に）、QR に残り時間「あと 0:58 で非表示になります」と「今すぐ隠す」。ペアリングが成立したら QR を閉じる。失効は A 型の確認（キャンセルが既定・⌘⌫） | `MobileTokenSection`、`MobileTokenViewModel.pairingQRHidesAt`・`handleAuthenticatedPairingRecorded` |

ターミナルの文字サイズを設定から変えたとき、開いているターミナルにもその場で効くようにした（`DashboardView` が保存値の変化を見て `applyTerminalFontSize` を呼ぶ）。

### 決定・食い違い

- **6 タブにした**（ユーザー承認）。凍結テスト `AcceptanceSettingsGroupingModelTests` の表を 6 グループ・12 区分に書き換えた。
- **ターミナルの範囲は現行の 9〜24pt のまま**。見本の 8〜32 は取らない（`TerminalFontSettings` の範囲はテストで固定）。
- **ボタンの文言は現行のまま**（「今すぐ確認」「通知テスト」「エージェント管理を開く」）。見本の「今すぐ確認…」「テスト通知を送る」「開く…」は、UI テストがこの名前でボタンを探すため取らない。
- **テーマの見本の文字は表示のときに訳す**。見本の文言（「本文の見本」など）は `AcceptanceThemePreviewModelTests` で固定されているため、モデルは日本語のまま、表示側で `AppLocalizedString` を引く。アプリアイコンの名前・QR の無効の理由・発行 / 失効の失敗も同じく表示側で訳す（`MobileTokenViewModel` の `String(localized:)` 2 か所はキーの文字列に変えた）。
- **選択中のテーマ・アイコンの枠はアクセント色のまま**。Codex は「注意状態以外の色」と指摘したが、デザイントークン（README）がアクセントを「輪・点・選択中の行」に定めているため従う。
- 見本にあっても現行に機能の無い項目は作らない（未決の一覧へ回す）: 匿名の利用状況、Dock のバッジ数、プッシュ通知、トークンの再発行。
- 英語で表示するとカスタムエージェントの名前に「(カスタム)」が付いたまま（既存の表示名。P11 では触れていない）。
- Debug 版は Release 版と設定の保存先を共有するため、目視では設定を変えていない（ターミナルの欄は保存されない範囲外の値だけを入れた）。

### テストの更新

- 凍結テスト `AcceptanceSettingsGroupingModelTests` を 6 タブの表に更新（ユーザー承認）。
- 実機 UI テスト `SettingsButtonAppearanceObservationTests`・`SettingsAuxiliaryButtonsAcceptanceTests`: 「通知テスト」が通知タブに移ったため、一般タブでは「今すぐ確認」だけを探し、通知タブを開いて「通知テスト」を探すようにした（確かめる内容は同じ）。Codex の「Tab で焦点が届かなくても通る」の指摘は、エージェント管理の既存の確認と同じ作り（焦点は記録だけ）なので変えていない。
- 新設 `DashboardFeatureTests/SettingsRedesignTests.swift`: ターミナルの入力が範囲内の整数だけを受け付けること。

### 検証

- `.claude/verify.sh` 合格（DesignSystem・AgentDomain・SessionFeature・DashboardFeature・app build）。`git diff --check` 問題なし。
- 実機 UI テスト（PhloxUITests）15 件合格（Codex の指摘の修正前に実行。修正はモバイル連携の表示と訳だけで、UI テストが触る一般・通知・エージェントのタブは変えていない）。
- Codex（gpt-6-sol high）の独立レビュー: 高 1・中 4。ペアリング成立で QR を閉じる、無効の理由と失敗の文を表示言語で出す、失効ボタンの VoiceOver 名に端末名を含める（「「%@」を失効」）を修正。残りは上の決定のとおり。
- Debug 版での目視（スクリーンショット）: ライト＋日本語で 6 タブすべて、QR の表示と残り時間・「今すぐ隠す」・失効の確認。ダーク＋英語で 6 タブすべて、テーマの見本とアイコン名の英語、T6b の赤い表示。
- VoiceOver: 見本（`10 Settings.dc.html`）に aria-label の指定は無い。テーマ・アイコンのタイルは名前と選択中、フルアクセスの行は固定の行名、失効ボタンは端末名を読む。
- 目視していないもの: QR の無効の理由（Tailscale ありの環境のため出ない）、ペアリング成立で QR が閉じるところ（実機の iPhone が要る）、失効ボタンの VoiceOver の読み上げ、Codex の修正後の画面。

## P12 通知・Dock・起動（11 Notifications and Startup）

### 対応表

| 見本 | 内容 | 実装箇所 |
|---|---|---|
| N5 完了 | 見出し「作業が完了しました: {名前}」、本文「次の指示を待っています。」。「入力待ち」はやめた | `SessionNotificationText`、`SessionCompletionNotifier.notifyCompleted` |
| N1 承認待ち | 見出し「承認待ち: {名前}」、本文に許可を求めている対象（コマンド全文 → 権限の文 → 承認の文の順）。Claude のツール使用許可（画面では承認カード）も承認待ちにそろえた | `ChatSessionViewModel.enterAwaitingApproval(prompt:notifying:)`・`receiveUserQuestion` |
| N2 質問待ち | 見出し「質問があります: {名前}」、本文に質問文。秘密の入力を求める質問は「入力を求めています」とだけ書く | 同上 |
| N3 エラー | エラーで止まったとき（ターミナル型の異常終了を含む）は完了と言わず「エラーで止まりました: {名前}」、本文にエラー文の 1 行目 | `notifyCompleted(sessionName:status:)` |
| N8 通知のテスト | 設定の「通知テスト」は専用の文言「Phlox の通知テスト」/「設定 > 通知」/「このように通知されます。」 | `SessionCompletionNotifier.notifyTest` |
| 設定の説明 | 「承認待ち・質問待ち・完了・エラーを macOS の通知で知らせます。」 | `SettingsView` |
| I1 初期化中 | アプリアイコン・「Phlox を起動しています」・小さな進行表示 | `InitLoadingView` |
| I2 / I3 初期化エラー | 注意バッジ付きのアプリアイコン、「Phlox を起動できませんでした」、エラーの内容を等幅の枠で（選択できる）、「終了」「再試行」（既定の見た目・⌘R）。Claude CLI が無いときの案内は残した | `InitErrorView`、`AppIconBadge`（P10 の E4 のアイコンを DesignSystem へ移して共有） |

通知の文言は、画面と同じアプリ内の表示言語で引く（App が起動時に `SessionCompletionNotifier.locale` を渡す）。これまでの `String(localized:)`（OS の言語）はやめた。

### 決定・食い違い

- **ターミナル型の Codex の質問は「承認待ち」のまま**。Codex の画面からは質問と承認を見分けられず、アプリ内の状態も承認待ちで表示しているため（通知の種類はアプリ内の状態の語彙にそろえる、という 11 の方針）。本文は出さない。
- **本文に「最後の返答の冒頭」は出さない**。完了の時点でその文を持っていないため、見本の括弧書き「次の指示を待っています」を使う。
- **サブタイトル「{プロジェクト} · {エージェント}」は出さない**。通知を出す側がその名前を持っていない。
- **ターミナル型の異常終了は、実行中からの終了だけ通知する**（現行の通知の条件どおり。承認待ち中の終了は通知しない）。条件は凍結テストで固定されている。
- 音は現行どおりすべて Glass（完了と対応待ちで分ける案は未決）。
- **「再試行」は ⌘R**。↩ も割り当てると ⌘R が外れる（1 つのボタンにショートカットは 1 つ）ため、見本の「再試行 ⌘R」を優先した。
- 画面の文言（`Text("…")` のキー）は環境の表示言語で同じカタログから引かれるため、P11 までと同じくそのままにした。

### テストの更新

- 凍結テストは変更していない（通知の条件の `AcceptanceNotificationGapTests`・`NotificationGapWhiteboxTests`、Dock の件数の `AcceptanceNotificationReachabilityTests`・`DashboardViewModelTests`）。
- 新設 `SessionFeatureTests/NotificationRedesignTests.swift`（3 件）: 種類ごとの見出し（完了に「待ち」が入らない）、承認の対象・エラーの 1 行目・質問文・秘密の質問の本文、通知テストの文言。

### 検証

- `.claude/verify.sh` 合格（DesignSystem・AgentDomain・SessionFeature・DashboardFeature・app build）。DesignSystem の iOS 向けビルド合格（`AppIconBadge` は macOS だけ）。`git diff --check` 問題なし。
- 実機 UI テスト（PhloxUITests）: 1 回目は「UI 自動化モードの有効化がタイムアウト」でテストが 1 件も始まらず失敗（環境要因）。再実行で全 15 件合格。Codex の指摘の修正（Chat の通知の種類と本文、`AppIconBadge` の macOS 限定）より前の実行で、UI テストはどちらにも触れない。
- Codex（gpt-6-sol high）の独立レビュー: 重大 1・高 3・中 3・低 1。iOS ビルド、質問の本文、ツール許可を承認待ちに、承認の対象をコマンド全文に、を修正。残りは上の決定のとおり。
- Debug 版での目視: 英語で通知テストが通知センターに新しい文言（見出し・サブタイトル・本文）で届くこと（おやすみモード中のためバナーではなく通知センターで確認）。起動エラー画面をライト＋日本語・ダーク＋英語で表示（データの置き場にファイルを指定して失敗させた）、⌘R で再試行、「終了」でアプリが終わること。
- 目視していないもの: 初期化中の画面（一瞬で終わる。文言はコードで確認）、承認・質問・エラー・完了の実際の通知（起こすには課金のあるエージェントが要る。文言はテストで確認）、バナーの見た目、VoiceOver の実操作。

## 追加検証（P12 の後）

未検証として残していた項目を、課金のかからない範囲で実際に確かめた。

### 見つけて直したもの

- **iOS のビルドが壊れていた**（P5 `a7cf77d` が原因）。共有の `ThinkingOrbState.orbLabel` を `orbLabel(locale:)` に変えたのに、iOS の `DSThinkingIndicator` を直していなかった。表示言語を渡す形に直した。iOS の画面は日本語の直書きのため、状態語は「Thinking...」から「考え中…」に変わる。
- **設定の読み上げ名の抜け**: 見出しのアイコンが記号名「paintpalette.fill」と読まれる（隠した）。表示言語・新規セッションの既定の開き方・端末の名前に読み上げ名が無い（付けた）。
- **スライダーの端の「80%」「200%」**: スライダーの端のラベルは押せるボタンになり、Tab の焦点が名前の無いまま止まっていた。スライダーの外の文字にした。

### 確かめたもの

- 実機 UI テスト 15 件合格（修正後の最新）。`.claude/verify.sh` 合格。iOS の PhloxKit の iOS 向けビルド合格とテスト 697 件合格（テストは macOS 上で実行）。Codex（gpt-6-sol high）の追加レビューは指摘なし。
- **本物の通知**: `agents.json` に bash スクリプトの偽エージェントを登録し、課金なしで起こした。実行中からのプロセス終了で「エラーで止まりました: Jasmine」（本文 exit code 143）、実行中から出力が止まって「作業が完了しました: Camellia」（本文「次の指示を待っています。」）が通知センターに届いた。
- **初期化中の画面**: CPU の優先度を下げて起動を遅らせ（`taskpolicy -b`）、窓だけを連続撮影して、英語＋ライトで「Starting Phlox」、日本語＋ダークで「Phlox を起動しています」を確認した。
- **D2**: git リポジトリのプロジェクトで worktree のセッションを作り、未コミットのファイルを置いて削除すると「セッション用 worktree を残しています」が出た。「Finder で表示」でその場所が開く。
- **E1**: ファイルタブで編集中に外からファイルを書き換えて保存すると「notes.txt は外部で変更されています」が出た。↩ でキャンセル（外の変更が残る）、⌘⌫ で上書きになることをファイルの中身で確かめた。
- **キーボード**: OS の「キーボードナビゲーション」を一時的にオンにし、Tab で焦点の移る先を AX で記録した（確認後に元の値へ戻した）。設定の 6 タブは、無効な「今すぐ確認」（Debug 版では押せない）を除き、すべての操作部品に届く。テーマのタイルには焦点の枠が出る。起動エラー画面は「終了」「再試行」を巡回する。上部のタブのアイコン部分は名前の無い焦点になるが、元の実装から同じ OS 標準のツールバーで、今回は変えていない。UI テストの Tab の確認は、OS のこの設定がオフのままでは一度も焦点に届かずに合格している（今回の記録で 0 件）。
- **読み上げ名（AX）**: 設定の全タブの操作部品の名前を読み出して確認した。失効ボタンは「Revoke “iPhone”」と端末名を読む。

### 確かめられなかったもの

- **D1（起動失敗）**: 見つからないエージェントは選べない（未検出で無効）。実行ファイルを後から消しても、セッションは作られてから中でエラーになる（D1 は出ない）。画面操作からは起こせない。
- **D9・D10（書き出し）**、**承認待ち・質問の通知**: チャット型のセッションが要り、開くと本物のエージェントが起動する（課金の承認が要る）。
- **ペアリング成立で QR が閉じるところ**: 実機の iPhone が要る。**QR を出せない理由の英語表示**: Tailscale が有効な環境のため、その状態を作れない。
- **VoiceOver の読み上げそのもの**: VoiceOver を起動するとこの Mac 全体の操作と音声が変わるため、起動していない。確認したのは VoiceOver が読む AX の名前まで。
- **iOS アプリ本体のビルド**: XcodeGen が入っていないため（導入は未承認）。パッケージまで確認した。

## 未実装・未決の一覧（P1〜P12 のまとめ）

現行の動作のまま残したもの。決めてもらえれば実装できる。

### 決定が要るもの（見本の分岐候補・案）

- 通知から直接「許可」「拒否」する（N1b）。
- Dock のバッジの数え方（見本は対応待ちの件数、現行は未読の完了の数）。変えるなら凍結テストの更新と、設定の「バッジに出す数」（T3）が要る。
- 無応答の通知（N4）、終了コードが 0 以外のときだけの終了の通知（N6）。
- プロジェクトごとのまとめ（N7）、対応したら通知センターから消す、通知のクリックでそのセッションへ移る、画面に見えているセッションは通知しない。
- 対応待ちの通知音を完了と分ける。
- 初期化中の段階の文言（見本も推測）、「ログを Finder で表示」（ログのファイルが無い）。
- APNs / Live Activity に同じ文言を渡す（iOS 側の表示と送る中身の取り決めが先）。
- 設定: 匿名の利用状況、Dock のバッジ数、プッシュ通知、トークンの再発行（見本にあるが現行に機能が無い）。見本のボタンの文言（「今すぐ確認…」「テスト通知を送る」「開く…」）、ターミナルの範囲 8〜32。
- タイルの矢印キーでの入れ替え、S8 の減光。
- F3 / E2（worktree の作り直し）、F4「既存の worktree を使う」。
- U4、シェルの再起動ボタン、衝突の相手の名前、再検出・インストールのリンク。
- 選択中のテーマ・アイコンのタイルの枠をアクセント色にしている（デザイントークンに従った。「アクセントは主ボタンだけ」の規則を優先するなら外す）。

### 英語表示で日本語が残るもの

- メニューバー、返信欄の送り先、プロバイダの理由の文、`WorktreeIsolationSpawnError` の文、`AgentSpawnError` の文（`String(localized:)` で OS の言語）、カスタムエージェント名の「(カスタム)」。

### 既知の制約

- A 型のダイアログは Esc で閉じない（SwiftUI で ↩ と Esc を 1 つのボタンに割り当てられない）。
- ターミナル型の Codex の質問は承認待ちとして通知する（見分けられない）。
- 通知の本文に最後の返答の冒頭、サブタイトルにプロジェクトとエージェントを出していない。

### 目視していないもの

- D1・D2・D9・D10・E1、承認・質問・エラー・完了の実際の通知、初期化中の画面、ペアリング成立で QR が閉じるところ、VoiceOver の実操作。

## F1 忠実度の修正: デザイン基盤（12 Design System）

2026-09-24 の忠実度監査（`docs/agent-output/ui-fidelity-audit/11-12-tokens.md`）の指摘のうち、トークンと共通部品の分を直した。画面ごとの直書き（文字サイズ・半透明の白・影）は F2 以降の各画面で直す。

### 決定（2026-09-24 ユーザー）

- 既定 2 テーマの弱い文字はモックの確定値（#8E8E94 / #75757B）。4.5:1 に届かないが、確定値を優先する。
- 入力欄の枠は全テーマで textPrimary の 14%（モックの `--line`）。ホバー・選択はダーク 0.06 / 0.09、ライト 0.05 / 0.075。
- テーマは README が正（Phlox＝既定ダーク、Phlox Light＝既定ライト）。

### 対応表

| 監査の指摘 | 内容 | 実装箇所 |
|---|---|---|
| テーマ切替で色が前のテーマのまま残る | `ThemeStore.resolved` が変更通知を読むようにし、`DSColor` の静的な読み出しも SwiftUI が追跡する | `AppTheme.swift`（`ThemeChangeSignal`） |
| ユーザー用ターミナルの配色が切替に追従しない | 生きている全ターミナルへ配色を当て直す | `TerminalCoordinator.swift`（`applyActivePaletteToAll`）、`DashboardViewModel.reapplyTheme()` |
| 端末の背景 | Phlox #141416、Phlox Light #1B1B1D、ANSI はモックの 8 色 | `AppTheme.swift` |
| 弱い文字がコントラスト補正で補助と同じになる | 既定 2 テーマは確定値をそのまま使う | `AppTheme.swift`（`designTheme`） |
| ホバー・選択の不透明度 | 上の決定の値。定義は `AppTheme.sidebarHoverOpacity(isDark:)` / `sidebarSelectedOpacity(isDark:)` の 1 か所 | `AppTheme.swift`、`Tokens.swift`（`fillSubtle` / `fillSelected`） |
| 入力欄の枠がライトでほぼ黒 | `composerBorder = border`（14%） | `Tokens.swift` |
| 小さい文字が 10pt | `DSFont.caption` / `captionStrong` / `monoCaption` を 11pt | `Tokens.swift` |
| 影 | グリッドのタイル・ポップオーバー（明暗で別）・ウィンドウをモックの値に | `Tokens.swift`（`DSShadow`） |
| 会話の accent・状態色 | 会話の accent を UI の accent に、文字は `accentInk`。承認待ち・エラーの色を対応待ち 4 状態の色に | `Tokens.swift`、`TranscriptTypography.swift`、SessionFeature の各セル |
| 操作部品の面 | `controlBackground`（Phlox は #3A3A3E）・`controlBorder`・`segmentTrack`・`fieldBorder`・`toggleOff`・`focusRing` を新設 | `Tokens.swift` |
| ボタン 4 種 | 主・副・破壊的・地の 4 種のスタイルを新設。使う画面は F2 以降 | `DSButtonStyle.swift` |
| トグル・セグメント・実行中の数・リサイズの取っ手 | モックの色と形に | `AccentSwitchToggleStyle.swift`、`NeutralSegmentedControl.swift`、`RunningCountBadge.swift`、`ResizeGripView.swift` |
| モード切替の高さ | 見た目は 22、押せる範囲は 24 のまま（task-34 の下限） | `DashboardToolbar.swift`（`ModeSegmentButton`） |
| 設定のテーマ見本が旧い値 | 入力枠 14%・選択面を実画面と同じ値に | `ThemePreviewModel.swift` |

### テストの変更（上の決定に合わせたもの）

- `AcceptanceSidebarTextContrastTests`: 既定 2 テーマの弱い文字だけを 4.5:1 の検査から外し、確定値そのものを検査する。本文・補助は全テーマで検査を続ける。
- `AcceptanceComposerBorderContrastTests`: 契約を「全テーマで textPrimary の 14%」に置き換えた。
- `DesignPaletteTests`・`AcceptanceThemePreviewModelTests`・`AcceptanceTranscriptTypographyTests`・`TokensTests`・`AppThemeTests`・`ChatTokenThemeTests`: 新しい値に更新。
- 新設 `ThemeChangeSignalTests`: テーマを変えると通知し、関係ないキーでは通知しない。

### 検証

- `.claude/verify.sh` 合格: DesignSystem 188、AgentDomain 545、SessionFeature 1054、DashboardFeature 1640（いずれも `--no-parallel`）、アプリのビルド。TerminalUI 79 合格。
- 並列実行（`--no-parallel` なし）では DashboardFeature が 10 分以上止まり、SessionFeature の `TerminationFlushRace` の 2 件が時間切れで落ちた。後者は単独の再実行で合格。どちらも verify.sh が直列で回す理由として書かれている既知の現象で、今回の変更との関係は調べていない。
- Codex（gpt-6-sol）のレビュー: 指摘 4 件のうち 3 件（テーマ見本の旧い値、Phlox の操作面の色、テストの除外範囲が広すぎる）を直した。「11pt 固定で文字サイズ設定に追従しない」は採らなかった。macOS には Dynamic Type が無く、`Font.caption` も固定 10pt のため。
- Debug 版をダーク・ライト・英語で撮影し、崩れが無いことを見た（`/tmp/phlox-audit/f1/`）。サイドバーの選択行がコーラル色なのは 03 の範囲で直す。

## F2 忠実度の修正: ウィンドウとタブ（01 Main Window / 02 Tabs）

監査 `docs/agent-output/ui-fidelity-audit/01-02-window-tabs.md` の指摘を直した。テーマ切替で子タブ列・対応待ちボタンが前のテーマの色で残る件（X1）は F1 の `ThemeChangeSignal` で直っている（切替後の撮影で確認）。

### 対応表

| 監査の指摘 | 内容 | 実装箇所 |
|---|---|---|
| A1 余白 | ツールバーの左 14・右 10・間 8、区切り線 1×18 | `DashboardToolbar.swift` |
| A1 タイトル幅 | 内容の幅、上限 300 / 210 / 150（幅の段階）。短い題名でも worktree ボタンが直後に来る | `DashboardToolbar.swift`（`CappedWidthLayout`） |
| A1 短縮 ID | 小文字 4 桁（「ed32」） | `DashboardToolbar.swift` |
| A1 / E4 worktree | ▾ を出す。メニューは見出し（プロジェクト名）・「git worktree で隔離する」・説明・「プロジェクト名を変更…」 | `DashboardToolbar.swift`（`WorktreeMenuButton`）、`AppRouter.projectRenameRequest`、`DashboardSidebarView.swift` |
| A1 表示モード | トラック `segmentTrack` 角丸 7、セグメント 22 高・左右 10・角丸 5・12/500、選択は `controlBackground`＋影 | `DashboardToolbar.swift` |
| A1 / D 対応待ち | full で 4 状態の記号、`controlBackground`＋0.5pt の縁、高さ 26・角丸 7、開いている間は選択の面。0 件は件数の丸を出さず淡くする | `AttentionListPopover.swift`（`AttentionButton`）、新設 `StateGlyph.swift` |
| 件数の丸 | 最小 18×16・角丸 8・白 11/700 | `DashboardToolbar.swift`（`CountBadge`） |
| A1 使用量 | 面なし・0.5pt の縁・高さ 26・角丸 7、使用量タブを開いている間は選択の面。取得前（0 件）は枠ごと出さない（X2） | `DashboardToolbar.swift` |
| D 使用量 compact / minimal | 「Cl 38 · Cx 62 · Cu 88%」、最小は 14pt の円グラフ＋数値（20% 未満は琥珀の ▲） | `UsageTopBarView.swift` |
| E1 一覧の行 | 面・枠なし、フォーカス行だけホバーの面＋内側 2pt の accent、状態記号 12＋エージェントの頭文字 16、2 行目以降の字下げ 44、「プロジェクト · 花名 · エージェント」、中身 11.5 等幅・角丸 5、ボタン 22 高・角丸 5 | `AttentionListPopover.swift`、新設 `AgentInitialTile`（`StateGlyph.swift`） |
| E1 未読完了 | 6pt の accent の点と経過時間 | `AttentionListPopover.swift` |
| インスペクタ上余白 | 上 10（40 だった） | `UsageSidebarView.swift` |
| D2 重ね表示 | 上端をツールバーの下 8 に | `DashboardView.swift` |
| E6 境界 | 当たり 8pt、ダブルクリックで既定幅、幅をウィンドウごとに保存（`@SceneStorage`。開閉は全ウィンドウ共有の `AppRouter` が持つため保存しない）。分割の区切りもダブルクリックで 50:50 | `ResizeGripView.swift`、`DashboardView.swift`、`SessionTabsContainer.swift` |
| C1 上段タブ | 内容の幅（最大 220）、左右 10・間 6、選択は 600、頭文字 10/700 等幅、状態 10.5/700、✕ は選択中だけ、＋はタブの直後 | `SessionTabBar.swift` |
| C7 隠れたタブ | 11.5/600・角丸 6 | `SessionTabBar.swift` |
| C1 子タブ | 左右 10、子タブの左右 10・間 6、記号 10/700、＋は子タブの直後、未保存の点は本文色 | `SessionTabsContainer.swift` |
| C4 ＋のメニュー | 見出し 600、記号の幅 22、「変更一覧 · 差分」（キー表記なし）、エージェント管理は「共通 ⇧⌘,」 | `SessionTabsContainer.swift` |
| C5 ターミナルの子タブ | 旧ドロワーの見出し行を外し、端末を全面に | `SessionTabsContainer.swift` |
| C6 右に分割 | 面 `--selText`・内側 2pt の accent・12/600・角丸 8 | `SessionTabsContainer.swift` |
| F メニュー | Phlox / ファイル / 表示 / セッション の 4 つ（「タブ」メニューを廃止）。ファイル: 新規・新しいタブ・ファイル・プロジェクト ｜ 書き出し・コピー ｜ ⌘W（行き先で「閉じる / セッションを削除… / グリッドから外す」）。表示: 表示モード・右に分割 ｜ サイドバー・インスペクタ・ターミナルのタブ・変更のタブ・レイアウト ｜ 文字を大きく・小さく・実寸。セッション: タブ 1–9・次前のタブ・対応待ち・次前のセッション・タイル 1–9（⌥⌘1–9、新設）｜ 許可・拒否・中断 ｜ 名前・別のプロジェクトへ移動・git worktree で隔離する（新設）｜ セッションを削除…（赤）。OS のウィンドウタブ（「タブバーを表示」）を出さない | `App/PhloxApp.swift` |

### 直していないもの

- X4（会話画面の左端の短い横線）: 04 会話で直す。
- エージェント管理を上段のタブの中身として開く（R:79）: README でエージェント管理は未設計のため、別ウィンドウのまま。
- 「セッションを削除…」は ⌘W をファイルメニューに付けたため、セッションメニュー側にはキー表記が無い（同じキーを 2 つの項目に付けられない）。
- 未確定のまま: 対応待ち 0 件の見た目（見本なし）、使用量の ▲ を文字段にも付けるか、ターミナル型の主タブ名、プロジェクト未選択時のタブ列。

### 検証

- `.claude/verify.sh` 合格（DesignSystem・AgentDomain・SessionFeature・DashboardFeature・アプリのビルド）。
- Debug 版をダーク（1680 / 1100 / 900 幅）・ライト・英語で撮影して確認（`/tmp/phlox-audit/f2/`）。英語のメニュー項目をアクセシビリティ経由で列挙し、訳の抜け（「エージェント管理…」「次のセッション」「前のセッション」）を足した。

### F2 のレビュー後の修正（F3 と同じコミット）

- ⌘W をファイルメニューの「閉じる」の位置（`CommandGroup(replacing: .saveItem)`）へ移し、標準の「閉じる / すべてを閉じる」を出さない。行き先が無ければウィンドウを閉じる。
- 子タブの分割・次前のタブは、単体表示でセッションを選んでいて共通ターミナルでないときだけ押せる（`canUseChildTabs`）。
- サイドバー・インスペクタの開閉の保存（`@SceneStorage`）を外した（開閉は全ウィンドウ共有のため、ウィンドウごとに保存すると食い違う）。
- worktree メニューの「プロジェクト名を変更…」は、サイドバーが隠れていれば開いてから名前の変更に入る。

## F3 忠実度の修正: サイドバー（03 Sidebar）

監査 `docs/agent-output/ui-fidelity-audit/03-sidebar.md` の指摘を直した。

### 対応表

| 監査の指摘 | 内容 | 実装箇所 |
|---|---|---|
| F2・F3 移動（高） | チャット型にも「プロジェクトを移動 / プロジェクトに割り当てる」を出す。チャット型は所属だけを付け替え、再起動しない（作業フォルダ・会話 ID・会話の記録はそのまま）ので確認を挟まない。復元で移動先の worktree 設定が作業フォルダを変えないよう、隔離しない印（`worktreeIsolationOptOut`）も保存する。自分用の worktree で動くチャットは移せない（worktree が元のプロジェクトのリポジトリのもののため）ので、項目を押せなくして「worktree で動いているチャットは移動できません」と出す。フォルダ選択と「移動するとセッションは再起動します」はターミナル型だけ。メニューバーの「別のプロジェクトへ移動」も同じ経路 | `DashboardViewModel.moveSession` / `canMoveSession`、`SessionPersistenceCoordinator.persistSessionWorkspace`（作業フォルダ nil は保存済みを残す）、`DashboardView.handle`、`DashboardSidebarView.sessionMenu`、`App/PhloxApp.swift` |
| F2 移動先の項目 | フォルダの印＋名前 | `DashboardSidebarView.swift` |
| F2・F4 メニューを開いた行 | ホバーの面＋内側 2pt の accent の輪。macOS ではメニュー内容の onAppear が呼ばれないため、ポインタが乗った行へのクリック（右クリック・⋯）で `NSMenu.didBeginTrackingNotification` が来たら開いたとみなす（キーボードで開いたメインメニューでは付けない） | `SidebarRows.swift`（`SidebarMenuOpenRing`） |
| F4 新規セッション… | サブメニューをやめ、押すと新規セッションの表を開く | `DashboardSidebarView.swift` |
| F6 行の高さ・案内 | 行の高さは 26 のまま。案内は欄の 4pt 下の吹き出し（ポップオーバー面・影・角丸 6・6 9・11 fg2）。LazyVStack では zIndex が効かず下の行に隠れるため、`anchorPreference` で位置を渡してスクロール領域の上に描く。幅が足りなければ折り返し、見えている範囲の下に収まらなければ欄の上に出す | `SidebarRows.swift`（`SidebarRenameHintBubble`）、`DashboardSidebarView.swift` |
| F6 案内の文言 | 戻り先を具体的に出す（「空欄で「#805AA9」に戻す」） | `SidebarRows.swift` |
| F6 入力欄 | 外側 2pt の accent の輪 | `SidebarRows.swift` |
| S1 シェブロン・フォルダ・範囲の印 | 文字「›」13、フォルダはモックの線画 16×13・線 1.2、範囲の印は 4 マス 12×11・線 1.4 | `SidebarRows.swift`、`StateGlyph.swift`（`FolderShape`・`GridScopeShape`） |
| S5 畳んだ行の要約 | 記号＋件数（「▲1」）11/600 fg2（ユーザー決定）。読み上げは文で出す | `SidebarRows.swift`（`SidebarSummaryText`） |
| S6 +n ピル | 面 `segmentTrack`・角丸 8、中身は記号 | `SidebarRows.swift` |
| S6 案内線 | `--guide`（本文色 13% / 14%） | `SidebarRows.swift`、`Tokens.swift`（`DSColor.guide`） |
| S3 空状態 | フォルダの線画 34×28、説明の行間 1.6 相当 | `DashboardSidebarView.swift` |
| 下端のボタン | 面 `controlBackground`（ダーク #3A3A3E）、縁 0.5pt `controlBorder`、影。エージェント管理・設定は 28×26 | `DashboardView.swift` |
| F8 プロジェクト削除 | 題「プロジェクト「X」を削除しますか?」、本文「このプロジェクトのセッション N 件（子セッション M 件を含む）を停止し、一覧から外します。会話は元に戻せません。」（0 件は「このプロジェクトを一覧から外します。」）、注記「フォルダ「~/…」とその中のファイルは削除されません。」。ほかのプロジェクトにある子孫も一緒に消えるので「…と、ほかのプロジェクトにある子セッション K 件を停止し…」と分けて書く。件数は削除と同じ範囲（サイドバーに出ない内部セッションも含む） | `DashboardViewModelSupportingTypes.swift`（`ProjectDeletionDialogText`）、`DialogTexts.swift`、`DashboardView.swift` |
| F9 移動確認 | 「、元に戻せません」を外す | `DashboardView.swift` |
| M 範囲中の行をもう一度押す | 範囲を外さない（ユーザー決定。凍結テスト `AcceptanceSingleModeProjectSelectTests` を承認のうえ更新） | `AppRouter.selectProjectFromSidebar` |
| 読み上げ | プロジェクト行の開閉状態を「展開中 / 折りたたみ」（英語 expanded / collapsed）。「展開」は操作名と同じキーで、英語が「Expand」になっていた | `SidebarRows.swift` |

### 直していないもの

- F6 空欄で確定したときの戻り先: モックは自動の名前（花名＋短縮 ID）だが、凍結テスト `AcceptanceSessionTitleStateTests.renameToBlankStaysEmptyManual` が「空欄は空の手動名（表示は短縮 ID）」を求めている。案内は実際の戻り先（短縮 ID）を出す。変えるにはテストの変更の承認が要る。
- F6 選択した文字の色（`--selText`）: SwiftUI の TextField では変えられない。
- F2・F4 メニューのキー表記（↩・⌘⌫）: 右クリックメニューにキーを付けると、ほかの場所のキーと重なる恐れがあるため付けない。「プロジェクトを削除…」「セッションを削除…」は `role: .destructive` だが、macOS の右クリックメニューでは赤く描かれない。
- S1 無応答の右端の時間（「無応答 2:14」）: 13 Review の決定を残す。
- S1 対応待ち 0・未読 0 のときの節: モックに見本が無いので出さないまま。
- S3 プロジェクト 0 件の「新規セッション」を押せなくする: 押しても始められないため残す。
- F7 セッション削除の出し方（シート）: 09 で扱う。
- 監査 5「実行中 2 件」との食い違い: 08 で扱う。
- F8 本文にターミナルの内容が消えることは書かない（モックの文言どおり「会話は元に戻せません」）。
- 名前変更の吹き出しを欄の上に出す場合: Debug のデータでは行が足りず（ウィンドウの最小の高さ 572）、実画面では再現できていない。コードだけで確認。

### 検証

- 追加したテスト: `moveSession_chatSession_changesProjectOnlyAndKeepsWorkingDirectory`（所属が移る・同じセッションのまま・保存済みの作業フォルダと会話 ID が変わらない・隔離しない印が付く）、`worktreeIsolation_movedChatRestoresInOriginalFolderWithoutWorktree`（隔離が有効な移動先でも元のフォルダで復元し worktree を作らない。印を外すと失敗することを確認）、`projectDeletionDialogText_message_namesChildrenInOtherProjects`、`projectDeletionDescendantCount_treatsHiddenChildInSameProjectAsOwn`。
- 独立レビュー（Codex）2 回。指摘 4 件（チャット移動後の復元・削除確認の件数・輪の誤表示・吹き出しの見切れ）を直した。
- `.claude/verify.sh` 合格（DesignSystem・AgentDomain・SessionFeature・DashboardFeature・アプリのビルド）。
- Debug 版をダーク・ライト・英語で撮影して確認（`/tmp/phlox-audit/f3/`）: 畳んだ行の「▲1」、右クリック中の輪と閉じた後に消えること、名前変更の吹き出しが下の行より前に出ること、プロジェクト削除の確認（キャンセルが既定・削除が赤）。

## F4 忠実度の修正: 会話画面（04 Session Chat）

監査 `docs/agent-output/ui-fidelity-audit/04-chat.md` の指摘を直した。文字の大きさ（本文 13・補足 11・コード 12）と列の最大幅 760 はユーザー決定、凍結テストの更新は「全部モックに合わせる」の承認による。

### 対応表

| 監査の指摘 | 内容 | 実装箇所 |
|---|---|---|
| A1 列・入力欄の最大幅 | 760 | `ComposerLayout.swift` |
| A1 本文の文字 | 本文 13・補足 11・コード 12・インラインコードは本文色＋淡い面 | `DesignSystem/TranscriptTypography.swift`、`RichMarkdownView.swift` |
| A1 ホバーの行 | ユーザー発言は吹き出しの左に「時刻→22pt のコピー」を下揃えで重ね、場所を取らない。エージェント側も右下に重ねる | `ChatMessageCells+Basic.swift`、`ChatMessageCopyButton.swift` |
| A1 吹き出し | `--code` 地・角丸 14・余白 9/13・列幅の 78%（`UserBubbleWidth`）・添付は本文の上（高さ 22・角丸 5・地の色） | `ChatMessageCells+Basic.swift` |
| A1 アバター | 直前がユーザー発言のアシスタントメッセージにだけ付ける。テーマを読んで文字色を更新（白文字で読めない不具合） | `ChatTranscriptView.swift` |
| A1 箇条書き・コードブロック | 「•」fg3・行の間 8。コードは `--code` 地・枠なし・見出し 28 と区切り線・言語は等幅の素の文字・文字だけの「コピー」・12pt | `RichMarkdownView.swift`、`ChatCodeBlock.swift` |
| A1・C2・B1 ツール実行の束 | 枠付きカード（`TranscriptCard`: 角丸 8・1pt 枠・見出し 32 の「› ラベル 要約 … しるし」）。「ツール実行 ×n」＋「Read X ほか n 件」。開くと 1 ツール 1 行（24pt・ツール名 44 幅・引数・「n 行」/「exit N」/「実行中」）、行を押すとその出力。実行中は既定で開き枠を濃く。Read などはファイル名だけ。表にない CamelCase のツール（ToolSearch など）は `$` を付けない | `TranscriptCard.swift`、`ChatMessageCells+CommandGroup.swift`、`TranscriptItemPresentation.swift`、`ChatRenderKit/ChatToolPresentation.swift` |
| A1 コマンド単体・exit | 1 件は「› コマンド $ …」の単独カード。出力先頭の「Exit code N」から「exit N」（0 は fg3、失敗は errInk 600）。出力は等幅 11.5・左 28・「error」を含む行は赤 | `TranscriptCard.swift`（`CommandExitCode`）、`ChatMessageCells+Structured.swift` |
| A1・C2 推論 | 「› 思考」カード。中身は 12.5・fg2・余白 9/12/10/28 | `ChatMessageCells+Structured.swift` |
| A1・C2 ファイル変更 | 「› 編集済み 相対パス +N −N」。差分は旧・新の行番号（hunk 見出しがある差分だけ。Claude の Write / Edit には無いので列ごと出さない）＋「+ 」「− 」、追加・削除の淡い面。下端に「さらに表示」「セクションをコピー」、差分は選択不可の注記。末尾の改行で出来る空行を出さない | `ChatMessageCells+Structured.swift`、`ChatMessageRenderCache.swift`、`Tokens.swift`（`diffAddedTint` / `diffRemovedTint`） |
| A1 タスクリスト | 「› タスク c/n 進行中のタスク」（完了は「すべて完了」）、✓ / ● / ○ | `ChatMessageCells+TaskList.swift` |
| A1 料金・エラー | 料金は「$0.42」（1¢ 未満は 4 桁）。エラーは塗りの三角・題 12.5 semibold・本文等幅・全幅 | `ChatMessageCells+Basic.swift` |
| H ヘッダ | 注意状態でないときは 12pt の文字「待機 · n分前に応答」「実行中 · 圧縮中」 | `ChatSessionHeader.swift` |
| B5 無応答・考え中 | 13 斜体のきらめき・経過 11.5 fg3・「無応答」・24pt の「中断 Esc」 | `ChatMessageCells+Structured.swift` |
| B6 圧縮中 | カード（犬 110pt・「会話を圧縮しています…」・「ステージ n / 6 · 名前」）。視差を減らす設定では止めた絵 | `CompactingIndicatorCell.swift` |
| 接続中 | 会話の中の行（二重の輪＋斜体） | `ChatTranscriptView.swift` |
| B7 長い会話 | 「以前のメッセージを表示（さらに n 件）」26pt のカプセル | `ChatTranscriptView.swift` |
| C3 サブエージェント | 行「↳ 説明 種類 … 状態 ›」、選択中は 2pt の accent。ヘッダの札（22・角丸 11）。右パネルの見出しは 56・「種類 · 状態」・「メインへ戻る」と ✕（Esc）。保存済みの記録でもライブと同じ 1 行（「Read /path」）にし、Claude Code が差し込む `<system-reminder>` を発言として出さない（整形は `StructuredChatKit.ClaudeToolCommand` に移して共有）。再起動後は一覧が戻らず中身を開けないので、その行は押せなくする | `ChatMessageCells+Structured.swift`、`ChatSessionAccessories.swift`、`SubAgentDrawerView.swift`、`SubAgentModel.swift`、`StructuredChatKit/ClaudeToolCommand.swift` |
| C4 巻き戻し | 幅 480・上から 110・題と説明・30pt の行（時刻 HH:mm）・キーの案内。高さは中身に合わせる（柔軟な枠で縦いっぱいに広がっていた） | `ChatHistoryRevertPicker.swift`、`ChatEscapeHandling.swift` |
| C5 履歴 | 「過去の会話から再開」17 bold・説明・角丸 9 のカード・「新しい会話を始める ⌘↩」 | `ChatHistoryStartView.swift`、`ChatSessionView.swift` |
| D1 Codex | 会話の中のカード「プラン c / n 完了」・子スレッド・停止ボタン | `CodexSessionSurface.swift` |
| D3 ターミナル型 | 56pt の見出し「名前 / エージェント（カスタム） · ターミナル · 作業フォルダ · ブランチ」と状態。端末は 12/16 の余白・端末と同じ地 | `SessionView.swift` |
| A1 入力履歴スクラバー | 2 件以上のときだけ、ホバーしていないときは淡く | `ChatInputHistoryScrubber.swift` |
| 読み上げ | カードの見出しは「ラベル、要約」＋「展開中 / 折りたたみ中」。VoiceOver で開閉できる（見出しのボタンに `children: .ignore` を付けて押下が効かなくなっていたのを外した）。サブエージェントの札は名前付き操作「サブエージェントを閉じる」、巻き戻しは「Esc 閉じる」を押せるボタンに、Codex のプランの行は「状態：タスク名」 | `TranscriptCard.swift`、`ChatSessionAccessories.swift`、`ChatHistoryRevertPicker.swift`、`CodexSessionSurface.swift` |
| 文字サイズ | Codex のカードも会話の文字サイズ設定に合わせる | `CodexSessionSurface.swift` |

### 直していないもの

- A1 項目どうしの間隔（モックは一律 14）: 凍結テストが役割ごとの 8 / 16 / 24 を求めている。
- Markdown の見出しの大きさ: モックに値が無い。
- 終了コード: 構造化された値がどのエージェントの経路にも無く、Claude の出力先頭の「Exit code N」から拾える分だけ。Codex / Cursor は出ない。
- 履歴の行の件数・最後の発言: データが無い。
- 右パネル見出しの定数 `SubAgentSplitLayout.headerHeight` は凍結テストのため 32 のまま（実際の見出しは `ChatSessionHeader.height` の 56 を使う）。
- モック側が「案」の項目（失敗したコマンドを自動で開く・最新のタスクを開く・推論の 1 行プレビュー・B3 完了の帯）。
- ツールバーの題（01 の範囲）。
- 再起動後、料金の行の入力・出力の内訳と「n分前に応答」が戻らない（使用量と最終応答時刻を保存していない。監査 7 と同じ既存の制約）。
- 再起動後はサブエージェントの中身を開けない（出力ファイルの場所を保存していない）。行を押せなくするところまで。
- タスクリスト（TodoWrite）と Codex のプランは、検証に使ったセッションにそのツールが無く、実画面では出せていない。テストとコードだけで確認。
- サブエージェントの記録に出る `SubagentHandback` の呼び出しは、ほかのツールと同じカードのまま出す。

### 検証

- 追加したテスト: `commandExitCode_parsesClaudeBashFailureHeader`、`turnCostFormat_hasNoSpaceAndTwoDigits`、`commandToolLabel_treatsUnlistedToolWithJSONInputAsTool`、`diffCodeView_dropsTrailingEmptyLineAndHasNoNumbersWithoutHunk`、`subAgentTranscript_formatsToolLikeLiveAndHidesSystemReminder`（実データと同じ形の記録）。
- 独立レビュー（Codex）1 回。指摘 4 件（札の ✕ に VoiceOver が届かない・プランの行に状態が無い・Codex のカードが文字サイズに追従しない・巻き戻しに閉じるボタンが無い）を直した。
- `.claude/verify.sh` 合格（DesignSystem 188・AgentDomain 546・SessionFeature 1058・DashboardFeature 1643・アプリのビルド）。ClaudeAgentKit 164・StructuredChatKit 26 も合格。
- Debug 版で有料の Claude / Codex セッションを動かし、ダーク・ライト・英語で撮影して確認（`/tmp/phlox-audit/f4/`）: ツール実行の束と開いた行（「263 行」「exit 1」）、ファイル変更の差分、コードブロック、料金、ヘッダ「待機 · たった今応答」、ターミナル型の見出し（FakeRun）、巻き戻しピッカー、サブエージェントの行・札・右パネル（Esc で閉じる）、Codex のエラーカード。
- 読み上げはアクセシビリティの操作で確認: カードの開閉（押下）、行の開閉、サブエージェントの札の「サブエージェントを閉じる」、巻き戻しの「閉じる」。VoiceOver 本体を使った読み上げの聞き取りはしていない。

## F5 忠実度の修正: 返答エリア（05 Reply Area）

監査 `docs/agent-output/ui-fidelity-audit/05-reply.md` の指摘を直した。フッターの並び（設定のチップをすべて左）はユーザー決定「モックに合わせる」で、凍結テスト `ComposerFooterLayoutAcceptanceTests` をその承認で更新した。Codex の権限は「今の 1 列のまま」（ユーザー決定）。

### 対応表

| 監査の指摘 | 内容 | 実装箇所 |
|---|---|---|
| R1〜R5 入力欄の面と縁 | 面 `fieldBackground`・縁 `fieldBorder` 1pt（縁は背面に描き、上に開く箱に線が乗らないように）・書いている間は外側 3pt の `focusRing` | `ChatComposer.swift` |
| R1 入力欄の上の宛先行 | 出さない。送れない理由は送信ボタンの説明に移した | `ChatComposer.swift` |
| R1・R5〜R7 プレースホルダ | 「メッセージを入力 — / でコマンド、@ でファイル」、実行中・承認待ち・質問待ちで文言を切り替え。色 fg3 | `ChatComposer.swift` |
| R2 強調 | `/コマンド` は accentInk 13.5 semibold、`@ファイル` は qstInk の等幅 12.5、キーワードは stlInk（紫）13.5 semibold | `ChatComposer.swift`、`Tokens.swift`（`composerKeyword`） |
| R2 入力履歴の刻み | 入力欄の右上に縦棒（幅 3・高さ 6/8/10、選択中 12 は accent）。ポップアップが開いている間は隠す。一覧は上に開く | `ChatInputHistoryScrubber.swift`、`ChatSessionView.swift` |
| R1・R4・R5 送信・中断ボタン | 直径 26・「↑」13 bold・無効と送信中は segBg に fg3。承認・質問待ちの間も ■ | `ChatComposer.swift` |
| R3 候補 | 入力欄の上に幅 460 で出す。見出し「コマンド / ファイル」・30pt の 1 行（名前・説明・出どころ）・選択は accentFill に白・下端にキーの案内。選択行へ自動で送る。長い名前は途中を省略（出どころを押し出さない）。グリッドのタイルでは 5 行 | `ChatComposer.swift`、`GridChatColumn.swift` |
| R8 添付 | チップ（30 高・22pt のサムネイル・#N・名前・サイズ・丸い ✕「添付を外す」）。上限の通知「5 枚目は追加できません。画像は 1 枚 4MB・最大 4 枚・合計 8MB までです。」を赤い箱で | `ChatComposer.swift`、`ComposerAttachments.swift` |
| R9 送信失敗 | 本文 12.5 textPrimary、「再送」24 高の枠付きボタン | `ChatReplyArea.swift` |
| R6 承認カード | 余白 11/13/12・間 9・11pt の菱形・「n分前から」・‹ › 20pt・題 13.5。対象の枠（カード地・角丸 7）。ボタン 28 高・角丸 7・12.5、キー表記は白 85% / fg3 | `ChatReplyApproval.swift` |
| R6b フォーカス | 縁の外に 3pt の輪（塗りでなく線。半透明のカードで色が濁っていた）。「許可」に 2pt の輪。補足「このセッション中は許可」の説明。答えたら入力欄へフォーカスを戻す | `ChatReplyApproval.swift` |
| R6 コマンド | 「$ 」fg3 ＋ 等幅 13、下に作業フォルダ · ツールの行（コマンドのときだけ） | `ChatReplyApproval.swift` |
| R6e ファイル | 28pt の行（A / M / D・パス・増減）と「› 差分を見る（n ファイル）」。押すと会話のファイル変更を開いてそこまで送る。英語は単数・複数を出し分け | `ChatReplyApproval.swift`、`ChatMessageCells+Structured.swift`、`ChatSessionView.swift`、`GridChatColumn.swift` |
| R6e Codex のファイル一覧 | Codex 0.156 の fileChange は `changes[]` で届くのに最上位の `diff` だけを読んでいて、会話にも承認カードにもファイルが出ていなかった。新規・削除の中身を +/− 付きの差分にそろえた（「+0」になっていた） | `CodexAppServerKit/AppServerCommonTypes.swift`、`CodexAppServerClient.swift`、`ChatSessionViewModel.swift` |
| R6f 権限の変更 | JSON をそのまま出さず「ネットワーク / 読み取り / 書き込み / 拒否」の行に分ける（Codex のスキーマ `RequestPermissionProfile`） | `ChatApprovalBroker.swift`、`ChatReplyApproval.swift` |
| R6 Claude の「このセッション中は許可」 | CLI の `permission_suggestions` から許可ルールの追加と作業ディレクトリの追加を `destination: session` にして `updatedPermissions` で返す。提案が無いときはボタンを出さない。補足文はファイル変更のときだけ「同じファイルへの変更」 | `ClaudeAgentKit/ClaudeChatClient+ControlProtocol.swift`、`ChatReplyApproval.swift`、`StructuredChatTypes.swift` |
| R7 質問カード | 余白 11/13/12・問い 13.5 semibold・選択肢 13・番号は等幅・自由入力は 30 高の自前の欄「その他（自由に入力）」・フォーカス中のキーの案内は「1–9 選択」「⌘↩ 回答を送信」「Esc 閉じる」 | `UserQuestionCell.swift`、`ChatReplyArea.swift` |
| R7c 秘密の入力 | 等幅 14・字間 2・「表示 / 隠す」・説明文 | `UserQuestionCell.swift` |
| R7d 回答済み・期限切れ | 12.5 の行。期限切れは全体を fg3 と点線の縁 | `UserQuestionCell.swift` |
| O1〜O3 モデル・effort のメニュー | 標準の Menu をやめて入力欄の上に開く箱（↑↓・↩・Esc。入力欄にフォーカスがあってもキーが届く。変換中・修飾キー付きは入力欄に渡す）。ほかの箱が開いたら閉じる。検索で絞ったら指す行を先頭へ | `ComposerPopupMenu.swift`、`ComposerSettingsControls.swift` |
| O4〜O6 権限 | 題と件数・ラジオの 2 行項目・Plan のスイッチ（読み上げ名つき）・脚注の箱。Plan のまま開いて解除したときは前のモードが分からないので manual（毎回確認）に戻す | `ComposerPopupMenu.swift`、`ComposerSettingsControls.swift` |
| O7 ブランチ | 見出しつきの箱（幅 300） | `ComposerContextIndicator.swift` |
| O8 コンテキスト | 右寄せ幅 240 の吹き出し「コンテキスト n%」「used / window トークン」。円は灰色の線 | `ComposerContextIndicator.swift` |
| チップ | 22 高・角丸 6・segBg・11.5・末尾 ▾。読み上げ名を箱の行に継がせない | `ComposerPopupMenu.swift`、`ComposerSettingsControls.swift` |
| 会話の末尾 | 返答エリアが伸びたとき（カードの補足など）、末尾に追従中なら最下部へ寄せ直す（末尾の行が隠れていた） | `ChatTranscriptView.swift` |

### 直していないもの

- O5 Codex の権限を「承認方式」「サンドボックス」の 2 段に分ける: ユーザー決定で今の 1 列のまま。
- O7 ブランチ切り替えの失敗は `.alert` のまま（凍結テスト）。
- R8 添付できないエージェントの扱い（モックの案 A〜C）と、モック側が「案」の項目。
- ↑ で入力履歴を呼ぶ案内、入力欄の高さ（モックの 74pt に対し概算）。
- Claude / Cursor の権限モードの件数はエージェントの実際の選択肢のまま。Codex の推論の深さはサブメニューでなく同じ箱の中の区分。
- effort は「effort: high」「low / medium / high / xhigh」の生の表記（モックどおり。独立レビューの指摘は撤回された）。
- 添付の #N の札、送信失敗の ✕ は残した。質問カードにフォーカスが無いときの Tab の案内も残した。
- 「このセッション中は許可」で Claude の `setMode`（モードの切り替え）は送らない。Codex のファイル変更のセッション許可は同じファイルだけに効く（Codex の仕様。別のファイルは再び聞かれる）。
- Codex の権限の変更は、スキーマに「追加するルール」「追加先」が無いので、ネットワーク / 読み取り / 書き込みの行で出す。
- 会話のファイル変更カードは、承認前や拒否後でも「変更済み」と出る（04 の範囲の既存の表示）。
- グリッドの入力欄は別の部品（標準のメニュー）で、チップの箱は無い。候補の箱はタイルの上端に接する。
- 会話のヘッダの権限の札（「自動」）は、入力欄のチップで権限を変えても追従しない（04 のヘッダの既存の挙動。F5 では触っていない）。

### 検証

- 追加したテスト: `ToolPermissionSessionScopeTests`（4 件。Claude CLI 2.1.280 が実際に送った `can_use_tool` の形で、`updatedPermissions` の中身まで）、`ApprovalPermissionRowsTests`（2 件）、`FileChangeItemTests`（3 件。`changes[]` の読み取り・新規 / 削除の +/−・frontmatter や `/dev/null` 形式を差分と取り違えない）。凍結テスト `ComposerFooterLayoutAcceptanceTests` は承認に基づき更新、白箱テスト `ComposerKeywordRenderingWhiteboxTests` は期待色を更新。
- 独立レビュー（Codex）4 回。1 回目の 6 件のうち 5 件（Plan 解除で強い権限に戻る・箱が ⇧↩ や変換中のキーを奪う・入力欄以外から開いたときにキーが届かない・検索後に ↩ が効かない・本文が「---」で始まる新規ファイルの差分）を直し、effort の表記は撤回された。2 回目で Plan の戻り先の読み込み前の穴を直した（入力欄以外の文字欄にキーを渡すのは他の欄のキーを奪わないための意図どおりとして残した）。3 回目の 1 件（絞り込み後に選択行へ送らない）を直した。
- `.claude/verify.sh` 合格（DesignSystem 188・AgentDomain 546・SessionFeature 1060・DashboardFeature 1640・アプリのビルド）。CodexAppServerKit 99・ClaudeAgentKit 168・StructuredChatKit 26 も合格。
- Debug 版で有料の Claude / Codex セッションを動かし、ダーク・ライト・英語で撮影して確認（`/tmp/phlox-audit/f5/`）: 候補（/ と @、選択行への追従、グリッド）、強調、履歴の刻みと一覧、フッターのチップと各箱（↓ 移動・排他・Esc・⇧↩ で改行・変換中の ↩ は変換の確定）、コンテキストの吹き出し、添付 4 枚と上限の通知、Claude の承認カード（フォーカス有無・S・補足・許可の輪）と「このセッション中は許可」が次の同じコマンドで聞かれないこと、質問カード（2 で選択・⌘↩・入力欄へ戻る）、Codex のファイル変更の承認カード（ファイル行・+3・「差分を見る」で開いてスクロール・同じファイルへの次の変更が聞かれないこと・N で拒否・英語の単数形）、Plan のオン→オフで元のモードに戻ること。
- 読み上げはアクセシビリティの操作で確認: 箱の行の名前、Plan のスイッチの名前、「差分を見る」の押下。VoiceOver 本体の聞き取りはしていない。
- 実画面で出せなかったもの: 送信失敗の通知、秘密の入力（Codex の質問が必要）、Codex の権限の変更の承認、Cursor のモデル検索、チップにキーボードフォーカスがある状態（入力欄にフォーカスが残るため作れない）。これらはテストとコードだけで確認。

## F6 忠実度の修正: グリッド（06 Grid）

監査 `docs/agent-output/ui-fidelity-audit/06-07-grid-inspector.md` の「1. 06 Grid」と「4. テーマ破綻」の 1・3〜5 を直した。07（インスペクタ・子タブ）は F7 で扱う。

### 対応表

| 監査の指摘 | 内容 | 実装箇所 |
|---|---|---|
| S1〜S7 端末タイルが空になる（バグ） | グリッドへ切り替えると、タイル A が端末を付けた後に一時的な mount が最後に付いてすぐ破棄され、端末を外していた。A には `updateNSView` が来ないので空のまま。所有者が外れたら通知し、画面上に残った mount が、端末がまだどこにも付いていないときだけ付け直す（画面外だったら画面に載った時点で）。同じコンテナでの端末切替で外れたときも通知する。所有権の規則は変えていない（ADR 0174 に追記） | `TerminalUI/TerminalView.swift` |
| S1〜S7 端末の色 | 常に暗い面（F1 の `AppTheme.terminalBackground` #141416 / #1B1B1D）。タイル内の端末に 8/10 の余白を取り、余白も同じ面で塗る | `PaneLayoutView.swift`、`SessionView.swift`（`terminalBackground` を内部公開） |
| S 全般 グリッド領域の背景 | `gridAreaBackground`（Phlox Light #F4F4F6・Phlox #18181A、ほかのテーマはウィンドウ色を一段暗く） | `Tokens.swift`、`SessionGridView.swift`、`DashboardView.swift` |
| S 全般 タイルの面 | `DSColor.background`（#FFFFFF / #1E1E20）に統一。ダークで面が 2 種類混ざらない | `PaneLayoutView.swift` |
| S 全般 表示範囲バー | 面を `DSColor.background` に。中央の列の中へ移し、インスペクタの上に掛からない | `GridModeBar.swift`、`DashboardView.swift` |
| S1〜S5 子タブ | 器 `segmentTrack`（0.065 / 0.08）、選択中の面 `DSColor.background` | `GridTileParts.swift` |
| S5 無応答の見出し | 「無応答 · 4分」（ほかの対応待ちと同じ形） | `GridTileParts.swift` |
| S3/S5 中タイルの質問 | 質問が 1 つ・単一選択・秘密でない・選択肢ありのときは、タイルの中で選択肢（11pt のラジオ）と「回答を送信」（選ぶまで無効）を出す。ほかは「開いて回答」。次の質問に切り替わったら選択を消す | `GridTileParts.swift`（`GridTileQuestionChoices`） |
| S3b/S4 承認カードのボタン | 高さ 22・角丸 5・左右 9（`compact`）。タイルのボタンはすべてこの寸法 | `ChatReplyApproval.swift`、`GridTileParts.swift` |
| S8 ドラッグ中の「つかんだもの」 | 230×30 の箱（状態 11 semibold textSecondary・タイトル 12 semibold・角丸 7・−1.5° 傾ける） | `PaneLayoutView.swift` |
| S8 ドロップ先の塗り | accent 0.14、ダークは 0.18 | `PaneLayoutView.swift` |
| S9 分割線のゴースト | 動かし先を 2pt の破線（[5,4]）に | `PaneDividerHandleView.swift` |
| S10 空の「絞り込みを解除」 | 面 `controlBackground`・縁 `controlBorder` | `DashboardView.swift` |

範囲トークンの面（S6、`fillSelected` を `--sel` の 0.075 / 0.09 へ）は F1 で直っていた。

### 直していないもの

- S8 元のタイルを薄く残す: `.draggable` にはドラッグの取り消しを知る手段がなく、端末の NSView は SwiftUI の重ね描きより上に出るため、薄めた面を確実に外せない。
- S1/S2 大タイルのチャット本文: モックの図（簡略版）と対応表（「返答エリアと同じ」）で描き方が違い未確定。会話画面をそのまま入れる今の形のまま。グリッドの入力欄の上の宛先行も残した。
- S10 空の説明文: 凍結テスト `AcceptanceGridScopeSummaryTests` が今の 3 通りの文言を固定している。モックの「〈プロジェクト〉の中で、選んだセッションがすべて終了または削除されました。」は、選んだセッションが範囲外にあるだけの場合に事実と違うので、今の文言のまま（変えるかはユーザーの判断待ち）。→ F8 の途中でユーザーが「モックに合わせる」と決めたので、下の「F6 補足」で直した。
- 端末の文字の大きさは単体表示と共通（モックの 11 にはしていない。同じ端末をタイルと単体で共有しているため）。
- 承認カードの「このセッション中は許可」は、そのエージェントが対応しているときだけ出す（モックは常に表示）。
- Cursor の使用量が 0% と出る件（監査 4-8）は値の正しさを確かめていない。
- 分割線は読み上げで「分割線」とだけ読まれる（既存）。

### 検証

- 追加したテスト: `TerminalMountReleaseTests`（5 件。画面上の mount は付け直す／画面外なら付けない／待つ間に付いた別の mount から奪わない／後で画面に載れば付け直す／同じコンテナで端末を切り替えた後も付け直す）。凍結テスト `AcceptanceTerminalMountOwnershipTests` は変更せず合格。`GridTileRedesignTests` の無応答の見出しの期待値を「無応答 · 2分」に更新（凍結ではない。モックに合わせた変更）。
- 独立レビュー（Codex）2 回。1 回目の 4 件（通知を待つ間に付いた mount から奪う・通知の時点で画面外だと付け直さない・領域の色が内側の背景に隠れる・次の質問に前の選択が残る）を直した。2 回目の 1 件（同じコンテナで端末を切り替えたときに通知しない）を直した。
- `.claude/verify.sh` 合格（DesignSystem・AgentDomain・SessionFeature・DashboardFeature・アプリのビルド）。TerminalUI 84 件も合格。
- Debug 版で撮影して確認（`/tmp/phlox-audit/f6/`）: ライト・ダークでの端末タイルの表示と、単体⇄グリッドの 3 往復後も端末が出ること、領域とタイルの面、分割線のドラッグ中の破線とラベル、タイルのドラッグ中の「つかんだもの」（状態・タイトル・傾き）とドロップ先の塗り・位置の説明（ダーク）、英語表示、⌘2 でのフォーカス移動。中タイルの質問は有料の Claude セッション（ウィンドウ 1700×700）で、選択肢を選んで「回答を送信」し、Claude が答えを受け取ったことまで確認した。
- 読み上げはアクセシビリティの情報で確認（タイルの名前、子タブ、分割線、ラジオの選択状態）。VoiceOver 本体の聞き取りはしていない。
- 撮っていないもの: ライトでのドロップ先の塗り（0.14）と、分割して挿入する側の塗り（中央の入れ替えだけ撮った）。コードだけで確認。

## F6 補足: グリッドの空の説明文（06 S10）

ユーザーの決定（モックに合わせる。凍結テストの変更を承認）で、選んだセッションが見えないときの説明を「〈プロジェクト〉の中で、選んだセッションがすべて終了または削除されました。」にした（絞り込みが無ければ「選んだセッションがすべて終了または削除されました。」）。選んだセッションが範囲の外にあるだけのときも同じ文になる。ほかの 2 通りは今のまま。表示言語で引くよう、文言を `GridScopeSummary.make(…locale:)` で作る。

- 変更した凍結テスト: `AcceptanceGridScopeSummaryTests.emptyMessageThreeBranchesAndNilWhenNotEmpty` の選択ありの 2 行（期待する文言だけ。分岐の数と条件は同じ）。
- 検証: `GridScope` のテスト 11 件合格。画面の確認は F8 の検証と一緒に行う（下の F8 節）。

## F7 忠実度の修正: インスペクタと子タブ（07 Inspector and Tools）

監査 `docs/agent-output/ui-fidelity-audit/06-07-grid-inspector.md` の「2. 07 インスペクタ」「3. 07 子タブの中身」と「4. テーマ破綻」の 2・6・7 を直した。モックの変更の画面はドロワー（PhloxAux）の形なので、タブ C の「変更」子タブの中に同じ骨組み（見出しの帯・共有の注意・一覧と差分・下端のコミット欄）を置いた。

### 対応表

| 監査の指摘 | 内容 | 実装箇所 |
|---|---|---|
| I/U 上端の余白 | 切り替えの上 12・左右 12・下 8 | `UsageSidebarView.swift` |
| I1/I2 副題 | 短い ID の「#」を外す。ターミナル型は「aider（カスタム）· ターミナル型」（プロジェクトと ID を出さない） | `SessionInfoPanel.swift` |
| I1 総コストの書式 | 小数 2 桁（`$1.84`） | `SessionInfoPanel.swift` |
| I1 総コストが「—」（バグ） | 復元した会話でも出す。調べると Claude CLI の `total_cost_usd` はセッションの累計（再開後も再開前の分を含む）で、これまで累計をターンのコストとして足し重ねていた（保存済みの会話で実測: 0.50 → … → 2.50、足すと $19.73）。ViewModel で直前の累計との差にし（取り消しで 0 に戻す。履歴から再開した直後は最初の累計を総コストにする）、総コストと最後の累計を保存して復元する。保存が無い以前の会話は最後の値を総額とみなす（ADR 0038 に追記） | `ChatSessionViewModel.swift`、`TranscriptStore.swift` |
| U1 カードの面 | `cardBackground`（ダーク #27272A） | `UsageSidebarView.swift` |
| U1 バケットのゲージの器 | `segmentTrack`（0.065 / 0.08） | `UsageSidebarView.swift` |
| U1 取得時刻 | 取得した直後や取得時刻がわずかに先でも「0 秒後に取得」と書かない（実画面と読み上げのラベルで出ていた。書式が渡した基準時刻を使わず、差 0 秒を「0 秒後」と書いていた） | `UsageSidebarView.swift` |
| U2 初回の骨組み | 幅 60% / 100% / 40%、面 `segmentTrack` | `UsageSidebarView.swift` |
| U5 Claude の値が古いとき | 注記だけ琥珀。数字とゲージは淡くしない（取得失敗のときだけ淡くする） | `UsageSidebarView.swift` |
| U1 / U6 ボタン | 「更新」22 高・11.5pt、「Cursor をインストールしに行く ↗」24 高・12pt の操作面＋0.5pt の縁 | `UsageSidebarView.swift`、`DSButtonStyle.swift`（高さ・文字・左右の余白を渡せるように） |
| 4-2 子タブの端末の色 #292937 | F1 で端末を常に暗い面にしたので直っていた（実測でセッションの端末と同じ色） | — |
| D7 サイズ変更の失敗 | 「[Phlox] シェルのサイズ変更に失敗しました（理由）。」を #FF8A8D の 1 行で。表示言語に合わせる | `TerminalPanelView.swift` |
| D8 文字サイズの表示 | 子タブ・共通ターミナルでも出す（F2 で見出しを外したとき一緒に出なくなっていた）。グリッドのタイルでは出さない | `TerminalPanelView.swift`、`DashboardView.swift` |
| D2/D2b 見出しの帯 | 高さ 34・panel 面・「エディタ」＋「プロジェクト · 変更 n」（Git でなければ場所）・更新（24×24） | `EditorPanelView.swift`、`SessionTabsContainer.swift`、`DashboardView.swift` |
| D6 共有の注意 | 見出しの下の全幅の帯（apvTint・11.5pt）、「このプロジェクトの全変更を表示しています。ほかのセッションの変更も含まれます。」 | `GitCommitPanel.swift`（`ChangeScopeNotice`） |
| D2b 一覧の幅 | 左右分割は 220 固定＋右に 1px の区切り。上下積みは高さ 190 まで | `EditorPanelView.swift` |
| D2 一覧の余白・行 | 上下 4・左右 6・行の間 1。チェックを行の中へ（13×13・オンは accentFill に白の ✓・オフは 1.2pt の fg3 の枠）、未保存の点（6×6） | `EditorPanelView.swift`（`CommitCheckbox`） |
| D2 右の見出し | 高さ 30 の帯に「差分 / 内容」・ファイル名・（読むだけの理由）・「ファイルタブで編集」 | `EditorPanelView.swift` |
| D2 差分の本文 | 11.5pt の等幅・行の高さ 1.7・幅 28 の行番号（追加と前後は新しい番号、削除は古い番号）・行全体を addTint / delTint で塗る・「+ 」「− 」。内容も行番号つき。塊の無い差分（権限だけの変更など）は git の見出しを出す | `EditorPanelView.swift`、`EditorCodeLines.swift` |
| D2 さらに表示 | 「さらに表示（残り n 塊 · m 行）」（内容は「残り m 行」） | `EditorPanelView.swift`、`EditorCodeLines.swift` |
| D2 ファイル未選択 | 大きな「使えない」表示をやめ、12pt の fg3 の 1 行に | `EditorPanelView.swift` |
| D2 / 4-7 コミット欄の位置 | 一覧の末尾から下端の固定へ（上に 1px の区切り・8×10・`background` の面）。一覧と差分の両方の幅に渡る | `EditorPanelView.swift`、`GitCommitPanel.swift` |
| D2 コミットメッセージ欄 | 見出しなし・角丸 6・6×8・12pt・field 面・1pt の fieldBorder | `GitCommitPanel.swift` |
| D2 ボタン | 24 高・左右 11・角丸 6・12pt。「コミット（n）」は主ボタン、「プッシュ」「PR を作成」は操作面 | `GitCommitPanel.swift` |
| D2 押せない理由 | ボタンの行の右に 11pt の fg3 で 1 行（プッシュと PR で同じなら 1 つ）。収まらなければ下へ | `GitCommitPanel.swift` |
| D5 処理の状態 | 7×9・角丸 7・12pt の箱。失敗は errTint の面に「!」（errInk）、成功は「✓」（ok 色）、✕ は 10pt。git の出力は要約と分け、code 面・10.5pt の等幅・84pt で畳む。PR の URL は 11pt の等幅 accentInk | `GitCommitPanel.swift` |
| D7 Git リポジトリでない | 中央に「Git リポジトリではありません」13pt semibold と説明「〈場所〉 には .git がないため、…」12pt | `EditorPanelView.swift` |
| D4 ファイルの編集 | 下端の帯をやめ、上に高さ 30 の帯（パス 11pt の等幅・「未保存」・「保存 ⌘S」20 高の主ボタン）。本文 11.5pt の等幅 | `SessionTabsContainer.swift`（`FileTabView`） |

### 直していないもの

- D1 端末の見出し（「再起動」「✕」「A− / A+」）: F2 で 02 モックに従い子タブの端末の見出しを外した（✕ は子タブ、文字サイズは ⌘+ / ⌘− とメニュー）。見出しの無い場所に「再起動」は置いていない。そのため D7 の文言の「再起動してください。」も付けていない。
- D4 ファイルの内容の行番号: 編集欄が標準の `TextEditor` で、行番号を並べられない。
- D4 保存の競合: 標準の `.alert` のまま（相手のセッション名は出せない）。
- D5 処理中の「…」の行（「コミットしています…」）: ViewModel がどの操作中かを持っていないので、ボタンの横の回転表示のまま。
- D5 失敗の要約の言い換え（「プッシュできませんでした。リモートに新しいコミットがあります。」）と、ViewModel が作る日本語の理由・状態の文言の英訳: 既存の ViewModel の文言のまま（英語表示でも日本語で出る）。
- U1 カードの印は `AgentBrandIcon` のまま（README の方針）。I2 の注記「…と表示します。」の語尾は実装の文のまま（モックはメモ調）。
- エラーで終わったターンの費用は、その場では総コストに入らず、次のターンの差に含まれる（凍結テストが「エラーでは使用量を出さない」と固定しているため）。累計は再開後も続くので、再開した後のターンでも取りこぼさない。
- 会話の下のターンのコストは、Claude では今回から累計でなく 1 ターン分になる（表示の意味が変わる）。以前に保存した会話の項目は累計のまま残る。CLI の履歴から再開した最初のターンはコストの行を出さない（再開前の累計がわからないため）。
- 総コストの保存に失敗した新しい会話は、復元時に最後のターンの額を総額とみなす（以前の会話との見分けがつかないため）。
- Cursor の使用量が 0% と出る件（監査 4-8）は値の正しさを確かめていない。

### 検証

- 追加したテスト: `RestoredSessionTotalCostTests`（8 件。保存した総額の復元・保存が無い旧データ・0.5 → 0.75 の 2 回目が 0.25・保存 2.5 から再開して 3.25 が届くと 0.75・保存した最後の累計を基準にする・取り消し後は 0 から数える・履歴から再開すると最初の累計が総コスト・ファイルへの保存）、`UsageTextAgoTests`（1 件）、`EditorCodeLinesTests`（4 件。行番号・残りの塊と行・内容の番号・塊の無い差分）。`GitWorkflowWhiteboxTests` の長い失敗出力の高さの上限を +120 から +140 に変更（凍結ではない。07 D5 の寸法で約 +131 になるため。畳まなければ +400 を超える）。凍結テストは変更していない。
- 独立レビュー（Codex）3 回。1 回目の 9 件のうち、総コストの保存の順序・読み込みの分離・差分の行の読み上げ・塊の無い差分・理由の識別子を直した。2 回目で終了時に総コストの保存を待つようにした。3 回目（差を ViewModel で取る形にした後）の 4 件のうち、保存する基準・取り消し・履歴からの再開の 3 件を直した。残る 1 件（総コストの保存に失敗した新しい会話は、復元時に最後のターンの額を総額とみなす）は保存の失敗時だけなので直していない。4 回目で 3 件の解決を確認し、保存を確かめるテストが無いという指摘にファイルへの保存のテストを足した。残した判断（端末の見出し・エラーのターンの費用・ViewModel の文言）は上のとおり。
- `.claude/verify.sh` 合格（DesignSystem 188・AgentDomain 546・SessionFeature 1068・DashboardFeature 1645・アプリのビルド）。ClaudeAgentKit 168 件・TerminalUI 84 件も合格（ClaudeAgentKit は最終的に変更していない）。
- 揺らぎ（今回の変更と無関係と判断）: SessionFeature の `MidTurnPersistenceWhiteboxTests` の 500ms 以内に戻るかのテストが、機械の負荷が高いとき（load average 13）の全体実行で落ちた（単独では 3 回とも合格。`TranscriptPersistenceQueue` だけを測るテスト）。DashboardFeature の全体実行が 1 回、凍結テスト `AcceptanceSessionTitlePersistenceTests` の標準エラーの取り込み（パイプを EOF まで読む）で止まった（並行するテストの子シェルがパイプを握るため。主スレッドが `readDataToEndOfFile` で止まっているのを `sample` で確認）。
- Debug 版で撮影して確認（`/tmp/phlox-audit/f7/`）: 変更の子タブ（ライト・ダーク・英語。見出しの帯・共有の注意・一覧・チェック・差分の行番号と行全体の塗り・内容の行番号・下端のコミット欄と理由）、インスペクタ（セッション: 副題・有料の Claude セッションの総コスト $19.73 → $2.50 に。再開して有料のターンを 1 回送り、そのターンのコストが $0.02、総コストが $2.96（2.94 + 0.02）になることを確認。アプリを開き直しても $2.96 が読み戻される、使用量: カード・ゲージ・取得時刻）、ファイルの子タブの帯、子タブの端末の色。
- 撮っていないもの: 上下積みの配置（中央の幅を 541pt 未満にできなかった）、Git リポジトリでないとき、処理の状態の箱（コミット・プッシュを実行していない）、未保存の点と「未保存」（実在のファイルを書き換えないため）、端末のサイズ変更の失敗。コードとテストだけで確認。

## F8 忠実度の修正（1）: ダイアログ（09 Dialogs）

監査 `docs/agent-output/ui-fidelity-audit/08-09-start-dialogs.md` の「2. 09 — ダイアログ」を直した。ユーザーの決定（自前のダイアログを作る）で、標準の `.alert` / `.confirmationDialog` / `NSAlert` をやめ、09 の中身をそのまま描く `DSDialog` に置き換えた。08（起動画面）は次の F8（2）で直す。

### 対応表

| 監査の指摘 | 内容 | 実装箇所 |
|---|---|---|
| 規則 A/B/C の見た目 | 幅 300・余白 20/16/16・間隔 10・中央揃え。面は `--box`（ライト #F6F6F7 / ダーク #2F2F33、`DSColor.dialogBackground`）。見出し 13pt bold、本文 11.5pt、注記 11pt fg2 | `DesignSystem/DSDialog.swift` |
| 規則 A 既定ボタンの色 | 既定は accentFill に白文字（↩ の表記つき） | `DSDialog`（`DSButtonStyle` の主ボタン） |
| 規則 A 破壊ボタン | 操作面＋0.5pt の縁に赤い文字 600、⌘⌫ の表記。左に置く（配列の順に並べる） | 同上 |
| 規則 ボタンの並び | 3 つ以上か、どれかの名前が 8 文字を超えるときは縦（表示言語の文字数で判定） | 同上 |
| 規則 A/C アイコン | アプリアイコン 56pt の右下に #E39A2D の三角と白い「!」（24×21、右 -4・下 -3）。B はアイコンだけ | `AppIconBadge.swift` |
| 規則 Esc | どの型も Esc でキャンセル（A 型は以前、↩ と Esc を同じボタンに付けられず Esc で閉じなかった） | `DSDialog`（`onExitCommand`） |
| D1 起動失敗 | 原因の文を等幅（10.5pt・code 面）で。次の手（エージェント管理を開く）を左、OK を既定 | `DashboardView.swift`、`DSDialogLog` |
| D2 後始末の失敗 | 見出しを言い切りに（「worktree を片付けられませんでした」「ブランチを片付けられませんでした」）。残った場所を等幅で。Finder で表示を左 | `DialogTexts.swift`（`CleanupWarningDialogText.title`） |
| D3 子セッションの一覧 | 本文の箇条書きをやめ、枠付きの表（行 26・名前と「Cx · 実行中」）。最大 6 件、超えた分は「ほか n 件」の行。未保存ファイルとフォルダの注記は表の下 | `DialogTexts.swift`（`SessionDeletionDialogText.rows/note`）、`DSDialogList` |
| D4 | 本文と「フォルダ「…」とその中のファイルは削除されません。」を別の段落（注記）に | `DashboardView.swift` |
| D5・フォルダ変更・子タブを閉じる | 同じ A 型に | `DashboardView.swift` |
| D6 名前変更のアラート | 廃止。サイドバーを隠しているとき・グリッドのタイルのメニュー・メニューバーからも、サイドバーを出して行の中で編集する（ユーザー決定） | `DashboardView.swift`（`beginSessionRename`）、`DashboardDetailView.swift`、`DashboardSidebarView.swift`（出した直後の依頼を拾う `onChange(initial:)`） |
| D8 スキル削除 | B 型（キャンセル・ゴミ箱に入れる〔既定〕） | `App/AgentConsole/Claude/ClaudeSkillsPane.swift` |
| D10 書き込み失敗 | ビューの外から出すので、アプリをモーダルにする独立したパネル（`DSDialogModal.run`）。「別の場所に保存…」を左、OK を既定、エラーを等幅で | `ChatTranscriptExportAction.swift` |
| E1 保存競合 | 「別のプログラム」→「別のセッション」。A 型 | `SessionTabsContainer.swift` |
| E3 衝突 | 09 の順（キャンセル・同じディレクトリで起動・worktree で分けて起動〔既定・一番下〕）と 09 の本文。相手の一覧は 08 F1 の形（状態 52 幅・対応待ちはその状態の色・右に種別の記号・背景なしの枠） | `StartScreenViews.swift`（`SpawnGuardSheet`） |
| E4 作成失敗 | 「隔離なしで起動」を左、「閉じる」を既定。git の出力を等幅で | 同上 |
| 見本外 | 端末の失効（設定）とブランチ切替の失敗（返答エリア）も同じ部品に | `App/SettingsView.swift`、`ComposerContextIndicator.swift` |

### 直していないもの

- E2 worktree の作り直しの確認: Phlox で作り直しが起きるのは、アプリ起動時の復元で worktree のフォルダが既に無いときだけ（新しいセッションは毎回新しいブランチを切る。`WorktreeIsolationPlanner` の `.recreate` は `.restore` の経路にしか無い）。フォルダが無いので失われる未コミットの変更も無く、モックの「作り直すと未コミットの変更は失われます」に当たる状態が起きない。確認を足していない。
- E4「既存の worktree を使う」: 新しいセッションのブランチ名と worktree の場所はセッションの ID から作るので、使い回せる既存の worktree が無い（作成の失敗は git の失敗かフォルダが git でないとき）。ボタンを足していない。
- D1 の本文（「codex の実行ファイルが PATH に見つかりません。」）: 原因の文は 1 つしか持っていないので等幅の欄だけに出す。
- D9 の前段: 会話の見出しのポップオーバーのまま（P10 の決定）。
- 削除の確認を閉じた直後に後始末の警告が出る場合の表示順: 標準のアラートのときと同じく、別々のシートで出す（Codex の指摘。起こすには worktree の削除の失敗が要り、実画面では確かめていない）。
- 09 の見本はウィンドウに付くシートと独立したアラートを同じ中身で描いている。ウィンドウ内の確認はシート（macOS 26 ではウィンドウの中央に浮く）、D10 だけ独立したパネル。

### 検証

- 追加・更新したテスト: `DialogRedesignTests`（D2 の見出し 2 通り、D3 の表の行・上限・「ほか n 件」・注記）。凍結テストは F6 補足の 1 件だけ変更。
- `.claude/verify.sh` 合格（DesignSystem・AgentDomain・SessionFeature・DashboardFeature・アプリのビルド）。1 回目は SessionFeature が `DSDialog` を見つけられずにコンパイルに失敗した。同じパッケージをビルドし直した後の 2 回目は全段合格（古いビルド結果を参照していたためと判断）。
- 独立レビュー（Codex）1 回。指摘 3 件のうち、書き込み失敗のパネルを閉じるときに解放するようにした。残り 2 件は上の「直していないもの」。
- Debug 版で撮影して確認（`/tmp/phlox-audit/f8/`）: ダーク＋日本語で D3（見た目・Esc で閉じる・↩ でキャンセル・削除されていないこと）。ライト＋英語で D4 と E3（Esc で閉じて起動しないこと）。サイドバーを隠した状態でメニューの「名前を変更…」からサイドバーが出て行の中の編集になること（Esc で取り消し）。
- 画面で確かめていないもの: D1（未検出の種別は起動できず、起動の直前に実行ファイルを消す手も絶対パスが使えず作れなかった）、D2・D10・E4・ブランチ切替の失敗（起こすには worktree の削除の失敗・書き込めない場所・git でないプロジェクト・実リポジトリのブランチ切替が要る）、D8・端末の失効（実物のスキル・端末に触れるため）、子タブを閉じる確認、VoiceOver の実操作（AX の並びは見出し→本文→ボタンを確認）。

## F8 忠実度の修正（2）: 起動画面（08 Start）

監査 `docs/agent-output/ui-fidelity-audit/08-09-start-dialogs.md` の「1. 08 — 起動画面」を、見本 `design_handoff_phlox_ui/designs/PhloxStart.dc.html` の数値に合わせた。

### 対応表

| 監査の指摘 | 内容 | 実装箇所 |
|---|---|---|
| S1 見出しと本文 | 見出し 24pt bold・字間 -0.3、本文 13.5pt・行間 1.7 相当・fg2。幅 520 まで・余白 64/24/24・段の間隔 26 | `StartScreenViews.swift`（`StartOnboardingView`） |
| S1 手順の番号 | 20pt の丸・11pt bold。手順 1 だけ accentFill に白、ほかは segBg に本文色。見出しは丸の横、本文は 30pt 字下げ。手順 1 の見出しを「プロジェクトを追加」に。⌘O は 11pt・0.85 | 同上 |
| S1 検出の一覧 | 枠だけ（角丸 9・塗りなし）。行の頭は 22pt の頭文字タイル。場所は fg2・末尾を省略。「検出済み」は緑、「未検出」は承認待ちの濃い色（見本の色の指定）。未検出の組込 CLI に「入手方法 ↗」（accentInk 12pt、各社の公式ページ＝ユーザー決定） | 同上、`AgentStartCards.swift`（`AgentInstallGuide`） |
| S1 手順 3 | 説明と「通知を許可…」（高さ 26）を 1 行に | 同上 |
| S2 未選択 | フォルダのアイコンをやめ、見出し 15pt semibold 本文色・本文 fg2・間隔 8 | `StartAreaPolicy.swift` |
| S3/S4 見出し | 名前 22pt bold・字間 -0.3、間隔 6。補足の行は間隔 8・区切りの点は fg3。worktree の札は高さ 20・左右 8・角丸 5・segBg。実行中の件数はサイドバーと同じ数え方（`runningSessionCount(in:)`） | `AgentStartCards.swift`（`AgentStartProjectHeader`）、`DashboardDetailView.swift` |
| S3 外周 | 上 48・左右 28・下 24、幅 860 まで、段の間隔 22。左右のうち 12 は幅を測る枠の外に置き、凍結の `AgentStartCardsLayoutPolicy`（左右 16 が前提）はそのまま | `AgentStartCards.swift`（`outerHorizontalInset`） |
| S5 列数 | 起動画面の幅が 900 以上で 4 列、未満で 2 列。縦積みは格子の 1 行（その列数）が入らないときだけ | 同上（`columnCount`） |
| S3 カード | 頭文字タイル 28pt（字 0.42）、名前 14pt semibold、2 行目「claude 2.1.280 · ~/.local/bin/claude」（版は `--version` で読む。読めなければ場所だけ）、番号は枠なしの 11pt 等幅 fg3、余白 14/12/12、最小の高さ 168、モデル・権限は 11.5pt・ラベル fg3（44 幅、英語で入らなければ広げて揃える）・値は本文色の 1 行、ボタンは 12.5pt | 同上（`AgentStartCardButton`）、`CLIVersionProbe.swift`、`StateGlyph.swift`（`AgentInitialTile` の `fontScale`） |
| S3 選択の輪 | ↩ で起動するカード（既定は 1 枚目）に常に accent の輪。起動中は外す。画面に出たら 1–N・矢印・↩ をすぐ受ける（文字の入力中は奪わない） | 同上 |
| S3 未検出のカード | 面は fillSubtle・0.85。「%@ が PATH に見つかりません。インストールすると、ここから起動できます。」と「入手方法 ↗」「再検出」。再検出は起動時の PATH を探し直し、見つかればその場で起動できるカードになる（アプリの開き直しが要らない） | 同上、`AppEnvironment.swift`（`AgentBinaryTable`・`redetectBinaries`）、`DashboardViewModel.swift`（`redetectAgents`） |
| S3 下の説明 | 見本の文体に。ただし「権限」は書かない（権限は設定の値を使い、引き継がないため） | `AgentStartCards.swift` |
| S5/F2 トースト | 丸い帯（高さ 34・popover の面と影）、「worktree を作成しています」と場所（11.5pt 等幅 fg2） | `DashboardView.swift` |
| E4 の出力 | F8（1）の `DSDialogLog` で対応済み | — |

### 直していないもの

- トーストの場所: 見本は作る worktree そのもののパスを出すが、Phlox の worktree の名前は起動の中でセッションの ID から決まる。起動前に分かる置き場所（`workspaceDirectory`）を出している。
- 再検出が探すのは起動時に読んだ PATH だけ。インストールで PATH に新しいフォルダが加わったときは、アプリを開き直すまで見つからない（Codex の指摘）。
- 縦積みの判定にカードの総数ではなく列数を渡している。見本の 2 列 / 4 列の格子に合わせるための判断。凍結テストは変えず、すべて通る（Codex は「凍結ポリシーの意図と違う」と指摘）。
- 見本のカスタムの種別には「入手方法」の行き先が無いので、カスタムの未検出カードは「再検出」だけ。

### 検証

- 追加したテスト: `AgentStartRedetectTests`。版の読み取り（3 形式と読めない出力）、終了信号を無視し孫プロセスが出力を握る CLI でも 5 秒で打ち切ること、4 列 / 2 列の境目（900）、起動後に置いた CLI を再検出が見つけ環境の写しからも見えること。テスト用の環境に PATH を渡せるようにした（`makeTestEnvironment(pathEnvironment:)`）。
- `.claude/verify.sh` 合格（DesignSystem・AgentDomain・SessionFeature・DashboardFeature・アプリのビルド）。レビュー後の修正の後にも 1 回合格。版を消す 1 行（下）はその後の変更で、`swift build` と上のテストだけ通した。
- 独立レビュー（Codex）2 回。1 回目の指摘 7 件のうち、版の読み取りが終わらない（高）・再検出と版の取得の競合・入力中のフォーカス取得・英訳の漏れを直した。残り 3 件は上の「直していないもの」。2 回目の新しい指摘（再検出の直後に古い版が一瞬残る）も直した。
- Debug 版で撮影して確認（`/tmp/phlox-audit/f8/`）: ライト＋日本語で 4 列の格子と版の表示、未検出のカード（`agents.json` に存在しない CLI を足した）、CLI を置いて「再検出」を押すと起動できるカードになること。ダーク＋英語で文言・ラベルの揃い・数字キー 3 と右矢印で輪が動くこと。空のデータフォルダ（`PHLOX_DATA_DIR`）で初回の案内（S1）。AX で カードの読み上げの並び（名前→版と場所→モデル→権限）。
- 画面で確かめていないもの: S2（プロジェクトもセッションも選ばない状態への戻し方が画面上に無い）、トースト（worktree 隔離で起動すると実リポジトリにブランチを作るため）、組込 CLI の「入手方法 ↗」（3 種とも入っている）、S1 の手順 3 の行（画面の下で、スクロールしていない）、VoiceOver の実操作。

## F9 忠実度の修正: 設定（10 Settings）

監査 `docs/agent-output/ui-fidelity-audit/10-settings.md` を直した。標準の `Form`（grouped）と `TabView` では見本の余白・区切り・色・タブの形を再現できないので、同じ中身を自前の部品で描き直した（`App/SettingsView.swift`。部品も同じファイルの末尾。App のファイルは xcodegen の登録が要るため新しいファイルを足していない）。

ユーザーの決定（2026-09-25）: テーマの色は今のまま（Phlox＝ダーク、Phlox Light＝白。並びと見本タイルだけ見本に合わせる）。ターミナルの文字の範囲は見本の案の 8〜32 に。凍結テストの変更は 4 件承認（ボタン名・窓の探し方・タブの絵・テーマの並び）。

### 対応表

| 監査の指摘 | 内容 | 実装箇所 |
|---|---|---|
| 全体 見出し | 「Phlox (Debug)」「設定」とアイコンの見出しをやめた。窓の題名はタブの名前 | `SettingsView.swift`（`navigationTitle`） |
| 全体 窓の大きさ | 幅 700、高さはタブごと（一般・エージェント 620、外観 660、通知 480、使用量 440、モバイル 560。見本の窓全体の値からタイトルバーの 28 を引いた中身の高さ）。中身が長ければスクロール | `SettingsView.windowHeight` |
| 全体 地・タブ列 | 地は `--bg`（ライト #ECECEF・ダーク #1E1E20）、タブ列は toolbar の面（#F6F6F7 / #2A2A2D）と下の 1pt の区切り。タイトルバーを透明にしてタブ列と 1 枚の面に（タブを切り替えると題名の変更で戻るので当て直す） | `SettingsTabBar`・`SettingsWindowChrome`、`Tokens.swift`（`settingsBackground`・`settingsTabSelected`） |
| 全体 タブ | アイコン 20・名前 11pt・最小幅 64・角丸 7。選択中は accentInk の文字と黒 7.5% / 白 10% の面。絵を見本に（外観＝半分塗りの丸、通知＝app.badge、エージェント＝slider.horizontal.3、使用量＝gauge.with.needle） | `SettingsTabBar`、`SettingsGroup.swift` |
| 全体 まとまり・行 | 見出し 12pt semibold、面は card（#FFFFFF / #27272A）・角丸 10・1pt の縁、行は余白 10/14・端から端までの区切り、名前 13pt、説明 11.5pt fg2、注記 11.5pt fg2 | `SettingsGroupBox`・`SettingsRow`・`SettingsLabel`・`SettingsDivider` |
| 全体 部品 | スイッチは accentFill、分段は segBg のトラック・選択中は操作面と影（高さ 20・12pt、← → で動かせ、読み上げは標準の分段と同じ）、ボタンは高さ 22・12.5pt、表示言語は枠のあるポップアップ、リンクは accentInk。Form 全体に掛けていた accent の tint をやめた | 同上（`SettingsSegmented`）、`DSButtonStyle` |
| T1 一般 | 説明を「⌘N や起動カードで ↩ を押したときの開き方」だけに、「今すぐ確認…」、版は 12.5pt・数字は等幅・fg2 | `generalForm` |
| T2 テーマ | 5 列・間隔 10。見本タイル（高さ 54・角丸 7、左 28% がサイドバーの色、右に 2 本の文字と accent の帯）。選択中は外側 2pt の accent、ほかは 1pt の縁。並びを Phlox → Phlox Light → … に | `ThemeTile`、`AppTheme.swift`（`ThemeStore.all`） |
| T2 アプリアイコン | 48pt・角丸 11、選択中は外側 2pt の accent、ほかは 1pt の縁、名前は id を等幅 11pt、注記なし | `AppIconTile` |
| T2 文字の大きさ | 端の値 11pt fg3、スライダー幅 150（目盛りなし。刻み 10% は値の丸めと ← →・読み上げの増減で守る）、値 12.5pt・幅 40。ターミナルは欄 56×22・▲▼・単位 12pt、説明は常体 | `appearanceForm`、`ChatFontSettings.snapped` |
| T6b 不正な値 | 欄に赤い縁と 3pt の淡い輪、下に 11.5pt の理由と現在の値。範囲を 8〜32 に | `terminalFontRow`・`settingsField`、`TerminalFontSettings.swift` |
| T3 通知 | 説明を常体に、「テスト通知を送る」 | `notificationsForm` |
| T4 エージェント | 各 CLI の説明を 1 行（例 Cursor「--force --sandbox disabled。オフにすると --auto-review --sandbox enabled」）。ボタンは「開く…」に ⇧⌘, を中に（読み上げは「エージェント管理を開く」）、定義の場所は 12.5pt fg2 | `agentsForm`・`BypassToggleRow` |
| T5 使用量 | 説明を常体に、見本に無い長い注記を外した | `usageForm` |
| L1 モバイル | 端末名の欄 180×22、QR のボタン高さ 22、注記を見本の 2 文に | `MobileTokenSection` |
| L2 QR 表示中 | 「表示中」は副ボタンの形で無効。QR は白地 132・角丸 8・1pt の縁、符号 112。案内 13pt semibold、残り時間 12pt 等幅 | 同上 |
| L3 接続済み | 日付だけ（時刻を外した）。失効は枠のある副ボタンの形に赤い文字 | `MobileDeviceRow` |
| L4 押せない理由 | 琥珀の文字（承認待ちの濃い色） | `MobileTokenSection` |
| L5 QR 作成の失敗 | 内容の先頭に帯（角丸 9・エラーの淡い面と縁・警告の絵・12pt） | `SettingsErrorBanner` |

### 直していないもの

- テーマの色（見本は Phlox が白・Phlox Light が暖色）: ユーザーの決定で今のまま。見本タイルの色も実際のテーマの色で描く。
- エージェントの注記: 見本の「確認なしで実行します」は Claude（サンドボックスは外さない）とカスタム（定義次第）で正しくないので、既存の正確な注記（`UIWording.settingsPermissionFooter`）のまま（Codex の指摘）。Claude の 1 行説明も見本の「hooks で確認を省く」ではなく実際の指定（bypassPermissions / auto）を書いた。
- L4 の文言: 見本の「ループバックだけで…」1 通りではなく、今の状態ごとの理由（Tailscale が無い など）を残した。
- L3 の「接続中 / 未接続」: 端末がいまつながっているかを Phlox は持っていない（`PairedDevice` はペアリング日だけ）。
- 見本で「未確認」「分岐候補」「推測」の項目（匿名の利用状況の送信、Dock のバッジ、プッシュ通知、トークンの再発行、L6）: 足していない。
- タイトルの位置: macOS 26 の窓は題名を左に置く。見本は中央。
- 操作面の色: ダークの副ボタンは 12 Design System の #3A3A3E（設定の見本は #4A4A4F）。ボタンの角丸は共通の 6（見本 5）。
- `ThemePreviewModel`: 設定では使わなくなったが、凍結の受け入れテストがあるので残した。

### 検証

- 凍結テストの変更（ユーザー承認）: `AcceptanceSettingsGroupingModelTests`（タブの絵の名前）、`AcceptanceThemePreviewModelTests`（テーマの並び）、`SettingsAuxiliaryButtonsAcceptanceTests`・`SettingsButtonAppearanceObservationTests`（窓はタブ列の識別子 `settings-window` で探す、ボタン名「今すぐ確認…」「テスト通知を送る」。「エージェント管理を開く」は読み上げ名なのでそのまま）。
- 追加したテスト: `ChatFontSnapTests`（10% 刻みへの丸め・範囲・近い位置で同じ値になること）。
- `.claude/verify.sh` 合格（DesignSystem・AgentDomain・SessionFeature・DashboardFeature・アプリのビルド）。レビュー後の修正の後にも 1 回合格。スライダーの丸めの直し（最後の変更）は DesignSystem のテスト（189 件）とアプリのビルドだけ通した。
- 独立レビュー（Codex）2 回。1 回目の指摘 5 件（注記の不正確さ〔高〕、Codex の説明、分段のキーボードと読み上げ、スライダーの小さな操作、使わない翻訳キー）を直した。2 回目で残りの翻訳キー 2 件とスライダーの値の往復（中）を指摘され、丸めを位置だけで決め、← →・読み上げの増減を 1 刻みにして直した。
- Debug 版で撮影して確認（`/tmp/phlox-audit/f8/`）: ライト＋日本語で 6 タブすべて。ダーク＋英語で外観と、ターミナルに 40 を入れたときの赤い縁・輪・「Enter a whole number from 8 to 32. Not saved (current value: 13)」（保存値は 13 のまま）。AX: タブは名前付きのボタン、分段はラジオボタン 2 つ、表示言語のポップアップ、スライダーの増減（AXIncrement / AXDecrement で 10% ずつ）。分段の ← →（クリックで焦点を置いてから、既定の開き方がターミナル⇄チャットに変わる。元に戻した）。
- 実行できなかったもの: 書き換えた UI テスト 2 本（XCUITest）。この Mac は自動化モードの有効化にユーザーの認証が要り（`automationmodetool`: 「This device requires user authentication to enable Automation Mode」）、テストの起動で止まった。スライダーの ← →（macOS の「キーボードで操作を移動」が無効で焦点が移らない）。モバイル連携の QR 表示中・押せない理由・作成の失敗・接続済みの一覧（QR を出すとトークンが発行されるため、また失敗の状態を作れないため）。VoiceOver の実操作。

## F10 忠実度の修正（1）: 通知と Dock（11 Notifications and Startup）

ユーザーの決定（2026-09-25）: 通知のボタンは「開く」だけ（許可・拒否は置かない）。通知の音は見本の案（完了だけ Glass、対応待ちは macOS の既定音）。

### 対応表

| 監査の指摘 | 内容 | 実装箇所 |
|---|---|---|
| N1〜N7 サブタイトル | 「{プロジェクト} · {エージェント}」。分からない部分は省く | `SessionNotificationText.subtitle(projectName:agentName:)`、`DashboardViewModel.notificationContext(for:)` |
| N2 完了の本文 | 最後の返答の 1 行目（チャット型）。無ければ「次の指示を待っています。」 | `completedBody(lastReply:)`、`ChatSessionViewModel.lastAgentReply` |
| N4 無応答 | 「応答がありません: {名前}」／「2 分以上反応がありません。最後の動作: {思考中の下段と同じ要約}」。チャット型で 120 秒反応が無くなったときに 1 回。復元時に実行中と推定しただけのターンでは出さない | `Kind.stalled`、`ChatSessionViewModel.updateStalled` |
| N7 まとめ | 通知の `threadIdentifier` をプロジェクトに。同じプロジェクトの対応待ちが 3 件以上で 1 枚「{プロジェクト} で 3 件が対応待ち」「承認待ち 2 · 質問待ち 1」「{最新の名前} ほか 2 件」に置き換える。まとめるかどうかは配信済みの一覧（反映が遅れる）ではなくメモリ上の記録で決める | `AttentionNotificationBook`、`SessionCompletionNotifier.post` |
| N1 ボタン・クリック | 「開く」（全種類共通）。クリックか「開く」で Phlox を前面に出し、今の表示モードのままそのセッションを選ぶ（⌘J と同じ選び方）。グリッドで範囲の外なら一時的にタイルに加える（範囲を変えると外れる）。まとめは、含むうちまだ対応待ちの最も新しいセッションへ | `AppDelegate.userNotificationCenter(_:didReceive:)`・`openSession`、`DashboardViewModel.revealInGrid` |
| N1 見ているセッション | 前面の Phlox で見えているセッション（単体では選択中、グリッドでは表示中のタイル）のことは、音も含めて知らせない | `SessionCompletionNotifier.isShowing`、`AppDelegate.isShowing` |
| N1 対応後 | 対応待ちが済んだら、完了は見たら、通知センターから消す。まとめは含むセッションがすべて済んだら消す。出した通知は識別子で待機中・配信済みの両方から消し、片付けは投稿と同じ列に並べる。前回の起動の分はセッションの復元が済んでから片付ける | `removeDelivered(attention:unseenCompletions:includesPreviousLaunch:)`、`DashboardViewModel.hasRestoredSessions` |
| 通知音 | 完了（とテスト通知）は Glass、対応待ち 4 種は通知の既定音。バナーを切って音だけ残している場合、対応待ちはシステムの警告音 | `SessionCompletionNotifier.post` |
| Dock | 数える対象を対応待ち（承認待ち・質問待ち・エラー・無応答）に。0 件は出さず、100 件以上は「99+」（`NSDockTile.badgeLabel`） | `AppDelegate.observeAttention`、`DockBadge.label(count:)` |
| モバイルの通知 | 英語固定だった本文（「Session completed」「Approval pending」）を、デスクトップと同じくアプリの表示言語で書く | `APNsNotificationBridge.NotificationEvent.body` |

### 直していないもの

- N6「セッションが終了しました」（exit≠0 のときだけ出す案）と Dock の数え方を選ぶ設定（T3）: 見本で分岐候補。足していない。
- 一部が済んだあとのまとめの件数: 次の対応待ちの通知が来るまで古い件数のまま。書き直すと通知が出し直され、バナーと音が鳴るので割り切った（コードに `ponytail:` の印）。
- 無応答はチャット型だけ。ターミナル型は最後の反応の時刻を持っていない。モバイルには無応答の通知の種類が無いので送らない。
- モバイルの通知で、質問は今も「承認待ち」の種類・本文で送る（種類を分けるには iOS 側の受信型の変更が要る）。
- 監査の `11-12-tokens.md` は作業ツリーに無く、照合は見本の HTML で行った。

### 検証

- 追加したテスト: `NotificationRedesignTests`（無応答の文言、サブタイトル、完了の本文、まとめの文言、まとめの記録の数え方）、`DockBadgeLabelTests`（0 / 99 / 100）、`chatStall_notifiesTheDesktopOncePerStall`、`revealInGrid_addsAnOutOfRangeSessionUntilTheRangeChanges`、`hasRestoredSessions_turnsTrueOnlyAfterStart`。モバイルの通知の期待値（`APNsNotificationBridgeTests`・`LiveActivityBridgeTests`）を日本語の本文に更新（テストの実行環境には訳が無いのでキーの日本語になる）。
- `.claude/verify.sh` 合格（DesignSystem・AgentDomain・SessionFeature・DashboardFeature・アプリのビルド）。AppBootstrap のテスト 161 件合格。
- 独立レビュー（Codex）6 回。見ているセッションでも鳴る音・グリッドの判定〔高〕、3 件のまとめの競合〔高〕、個別とまとめの併存〔高〕、復元前の片付けで有効な通知まで消す〔高〕、グリッドの範囲外、まとめのクリック先、片付けと投稿の競合を直した。6 回目で新しい指摘なし（残りは上の割り切りだけ）。
- Debug 版での確認（背面で起動し、アクセシビリティ経由と制御用 API だけで操作。通知の中身は通知センターのデータベースを読み取り専用で読んだ）: 完了の通知（「作業が完了しました: …」「CapWeave · Claude Code」、本文が最後の返答）、質問の通知と「開く」の分類、Dock が 1 → 0、回答後に通知センターから消えること、3 件の質問を同時に送って 1 枚「CapWeave で 3 件が対応待ち」「質問待ち 3」になり個別の通知が残らないこと、Dock が 3、全部に答えるとまとめが消え Dock も消えること、見ていない完了の通知だけが残ること。
- 実行できなかったもの: 通知のクリックと「開く」での移動（押すにはあなたの画面を使うため）。前面で見ているときに知らせないこと（Phlox を前面に出す必要があるため）。無応答の通知の実物（2 分間反応の無いターンを作れなかった。単体テストのみ）。モバイルへの送信の実物。音の聞き分け。作り直した Debug 版からは、前のビルドが出した通知が見えない（署名が変わるため）ので、ビルドをまたいだ片付けは確かめていない。

## F10 忠実度の修正（2）: 起動中と起動エラー（11 Notifications and Startup）

ユーザーの決定（2026-09-25）: データの移行に失敗したら、見本どおり起動を止めてエラー画面を出す（以前は移行に失敗しても起動を続け、新しい置き場を作っていた）。

### 対応表

| 監査の指摘 | 内容 | 実装箇所 |
|---|---|---|
| I1 起動中 | 17pt 太字の見出し、幅 240・高さ 4 の往復する進捗帯（視差効果を減らす設定では止める）。1 秒経っても終わらないときだけ出す。読み上げでは進行中の表示として読む | `InitLoadingView`、`StartupProgressBar` |
| I2 サーバーを開始できない | 「制御用のサーバーを開始できません。」と原因の文。制御用・フック用のサーバーの開始の失敗を型で見分ける | `InitFailure.serverFailed`、`CompositionRoot.isServerStartFailure` |
| I3 移行できない | 「以前のバージョンのデータを移行できませんでした。データは消えていません。」。移行の失敗で起動を止める。旧アプリ（AgentDashboard）が起動中で移行を見送ったときも止め、「終了してから再試行してください」と案内する（止めないと新しい置き場ができ、以後は旧データが見えなくなる） | `MigrationOutcome.startupFailureReason`、`CompositionError.migrationFailed`、`InitFailure.migrationFailed`・`legacyAppRunning` |
| エラー画面の形 | 等幅 11pt・左揃えの原因の枠（コード背景・角丸 7）。ボタンは「ログを Finder で表示」「終了 ⌘Q」「再試行 ⌘R」（既定） | `InitErrorView` |
| ログ | 失敗を時刻つきで `~/Library/Logs/Phlox/startup-error.log` に追記。今回書けたときだけ「ログを Finder で表示」を押せる | `InitFailure.writeLog()` |
| 再試行 | 初期化の途中でもう一度押しても重ねて走らせない | `PhloxApp.initialize()` |
| Claude Code が無い | 説明を 1 文にまとめ、インストールのコマンドを原因の枠に出す | `InitErrorView.description` |

### 直していないもの

- 見本 I3 のログの例（JSON が壊れている）: 移行は中身を検査せずにコピーするので、この場合は移行の失敗にならない（読み込みの側でファイルを退避して空として扱う）。見本のログは例示と見て、検査は足していない。
- I2 の案内は見本より短い（別の Phlox や他のアプリがポートを使っている可能性の文を出していない）。制御用・フック用のサーバーは指定のポートで失敗すると空いているポートで取り直すので、ポートの競合は原因にならないため。
- 同時に 2 つ起動して移行のロックが取れなかったとき、今は起動エラーの画面になる（以前は移行を見送って起動を続けた）。

### 検証

- 追加したテスト: `onlyFailedMigrationStopsStartup`（失敗だけが起動を止め、Debug 版の見送りなどは止めない）。`oldRootSymlinkIsRejected` と `runningLegacyApplicationSkipsMigrationForVisibleNotification` に、起動を止めることの確認を追加。
- `.claude/verify.sh` 合格（DesignSystem・AgentDomain・SessionFeature・DashboardFeature・アプリのビルド）。
- 独立レビュー（Codex）3 回。旧アプリ起動中に旧データが見えなくなる〔高〕、再試行の重複〔高〕、ログが無くても押せるボタン、進捗帯が読み上げから外れていた点、旧アプリ起動中の案内が無い点を直した。3 回目で新しい指摘なし。
- Debug 版での確認（背面で起動し、アクセシビリティ経由だけで操作）: データの置き場を書けない場所にして起動エラーを出し、ライト・ダーク、日本語・英語で見た目を撮影。ログに追記されること。「再試行」で初期化がやり直され、ログにもう 1 行増えること。通常の起動で 1 秒後に起動中の画面が出て、その後ふつうに開くこと。
- 実行できなかったもの: I2・I3・旧アプリ起動中の画面の実物（Debug 版は移行を行わず、サーバーの開始の失敗も起こせないため）。⌘Q・⌘R のキー操作（あなたの画面を使うため）。進捗帯の読み上げ（今回の起動が速く、起動中の画面のうちにアクセシビリティで読めなかった）。

## F11 忠実度の修正: デザインシステムの残り（12 Design System）

F1〜F10 のあとに残っていた指摘を、監査（`11-12-tokens.md`）と今のコードで照合し直した（Codex で調査）。残っていたのは 7 件で、そのうち 5 件を直した。

### 対応表

| 監査の指摘 | 内容 | 実装箇所 |
|---|---|---|
| S ヘッダの対応待ちに経過が無い | 「質問待ち · 1分」。対応待ちに入った時刻から数え、1 分の境目ごとに更新する | `ChatSessionHeader.stateView` |
| U ヘッダで共通の状態部品を使っていない | 対応待ちは `StatusCapsuleBadge` で描く（無応答の「無応答 2:14」は秒で動くので専用のまま） | `ChatSessionHeader.stateView` |
| S 読み上げに経過が無い | サイドバーの行を「待機、42分前」「承認待ち、3分前から」（英語は「idle, 42m ago」「question, since …」）。1 分未満は付けない。経過の起点から 1 分の境目ごとに作り直す（経過の無い行では時計を動かさない） | `SidebarSessionRow.accessibilityText`・`elapsedSince` |
| P 件数バッジの寸法 | 最小幅 18・高さ 16・11pt 太字 | `DashboardSidebarView.attentionSection` |
| T 直書きの影 | 「最新へ移動」のピルをポップオーバーの影と 0.5pt の縁に（見本の `--shadow`） | `ChatTranscriptView` |

### 直していないもの

- 文字サイズの段（24/17/14/13/12.5/12/11.5/11）を全画面でトークン経由に揃えること: 見本の画面そのものに段の外の値（例: 10.5）があり、F2〜F9 で画面ごとに見本の値へ合わせ済み。直書きをトークンに置き換えるだけの変更は見た目が変わらないので見送った。
- 角丸 5pt の直書き（セグメントの選択面）: 見本にある部品固有の値なので不一致ではない。
- 弱い文字色の補正・小さい文字の 11pt 一律化・無応答の経過の形式・グリップの通常時の線: F1・F3・13 Review の決定どおり（作業記録の各節）。
- 対応待ちの一覧の読み上げは「2 分前から」（数字の後に空白）で、今回のサイドバー行（「2分前から」）と書き方が違う。一覧は前からある書き方で、今回は触っていない。

### 検証

- `.claude/verify.sh` 合格（DesignSystem・AgentDomain・SessionFeature・DashboardFeature・アプリのビルド）。読み上げの経過にはテストを足していない（行の中の非公開の組み立てのため。実機で確認した）。
- 独立レビュー（Codex）3 回と修正 1 回。ヘッダの更新の起点、読み上げの経過が古いまま残る点、更新の起点が表示時刻だった点、経過の無い行でも時計が動く点を直した。3 回目は低の 1 件だけで、それも直した。
- Debug 版での確認（背面で起動し、アクセシビリティ経由と制御用 API だけで操作。質問は実際の Claude Code セッションに出させた）: ライト・日本語でヘッダが「質問待ち · 1分」、サイドバーと揃うこと。待機の行の読み上げが「Azalea、待機、1か月前、Codex」。ダーク・英語でヘッダが「question · 1m」、待機の行の読み上げが「Azalea, idle, 1mo ago, Codex」。質問には答えて待機に戻した。
- 実行できなかったもの: 対応待ちの行の読み上げ（「…、質問待ち、1分前から、…」）。質問を出させたセッションが畳んだ親の下にあり、行が表示されていなかった（見えたのは前からある対応待ちの一覧の読み上げ）。VoiceOver での実際の読み上げ（アクセシビリティの値は確認した）。件数バッジの寸法の実測（撮影で見た目だけ確認）。

## F12 見送り分の再対応（1）: グリッド（06 Grid）

F1〜F11 で見送った項目を、ユーザーの判断（`0037-ui-redesign-decisions-2.md`・`0037-ui-redesign-c-decided.md`）に沿って直した。グリッドで直したのは 5 件。

### 対応表

| 見本の指示 | 内容 | 実装箇所 |
|---|---|---|
| 入力欄の上に宛先の行が無い | 宛先の行を消した（ユーザー判断。送れない理由は別の場所に出さない） | `GridChatColumn`・`GridComposerBar` |
| S8 ドラッグ中は元のタイルを薄く残す | ドラッグ元のタイルを不透明度 0.4 に。離したらマウスの状態を見て戻す | `PaneLayoutView.beginDrag`・`PaneTileView.isDragSource` |
| キーボードでタイルを入れ替える | ⌥⌘⇧＋矢印で、その辺に接するタイル（接する長さが最も長いもの）と入れ替える | `PaneTree.neighbor(of:toward:)`・`DashboardViewModel.swapGridTile` |
| キーボードで分割線を動かす | ⌃⌥＋矢印で、フォーカス中のタイルの右／下の線（無ければ左／上）を 5% 動かす。縮む側が最小（240×160）を割るなら動かさない | `PaneTree.nudgedDivider`・`nudgingDivider`・`DashboardViewModel.nudgeGridDivider` |
| グリッドの端末の文字は 11pt | 単体のときの文字サイズを 11/11.5 倍にしてグリッドで使う（0.5pt 刻み、最小値あり）。子タブの端末も同じ | `TerminalFontSettings.gridSize`・`TerminalPanelView(isInGridTile:)` |

8 個のキー操作は「セッション」メニューに置いた（英語の文言も追加）。

### 直していないもの

- ドラッグ開始の検知はドラッグのプレビューの表示時に行う。タイルの見出しに `.draggable(` があることを凍結テスト（`AcceptancePaneLayoutViewTests`）が固定しているため、`.onDrag` に替えられなかった。Esc でドラッグを取り消したとき、マウスのボタンを押している間は薄いまま残る（離すと戻る）。
- ⌃⌥＋矢印は VoiceOver の操作キーと重なる。見本の割り当てのまま（VoiceOver 使用中は VoiceOver が優先する）。
- C-38（「このセッション中は許可」を常に出す）: 許可の範囲を持たないエージェントでは実現できないため直していない。
- C-34（大きいタイルを見本のように簡略化する）: グリッドで会話を遡れなくなるため、ユーザーの判断待ち。
- 絞り込みで表示が平坦になったときの分割線の下限判定と、縦方向の 160pt の下限は、テストで確かめていない（コードでは同じ経路を通る）。

### 検証

- `.claude/verify.sh` 合格。テストを足した（`PaneKeyboardNavigationTests`・`TerminalGridFontSizeTests`・`GridTileRedesignTests.keyboard_swapsWithTheNeighborAndNudgesTheDividerWithinTheMinimum`）。
- 独立レビュー（Codex）3 回と修正 2 回。表示用に平坦化されたツリーで線を動かすと向きが逆になる点（高）、最小の判定が余白と隙間を除いていない点（中）、子タブの端末の文字サイズ（中）を直した。3 回目は高・中なし。
- Debug 版での確認（背面で起動し、アクセシビリティ経由のメニュー操作と撮影だけ）: ライト・日本語で宛先の行が無いこと、「タイルを左と入れ替え」で Poppy が左の列へ移ること、窓が狭いときは「分割線を左へ」で線が動かない（隣が 240pt を割る）こと、窓を広げると線が左へ動くこと。ダーク・英語で宛先の行が無く、画面の文言が英語で出ること。メニューの項目は既存の項目も含めて日本語のままだった（メニューは OS の言語に従う、前からの挙動）。
- 実行できなかったもの: ドラッグ中の薄い表示の目視（実際のドラッグはユーザーの操作を奪うため行っていない）。キー入力そのもの（メニュー経由で同じ処理を呼んだ）。

## F12 見送り分の再対応（2）: 使用量（01 D・07 Usage・PhloxAux）

### 対応表

| 見本の指示 | 内容 | 実装箇所 |
|---|---|---|
| Claude の注記「43 分前に取得 · 古い可能性」 | 30 分（閾値は据え置き）を過ぎたら「N 分／時間／日前に取得 · 古い可能性」。英語は「Fetched 43m ago · may be outdated」。使用量カードは表示言語に従う。凍結テストの文言の変更はユーザー承認済み | `ClaudeUsageStaleness.note`・`UsageCLICard` |
| 01「残り 20% 未満は 3 段階とも琥珀＋▲」 | 文字だけの段階（Cl 38 · Cx 62 · Cu 88%）にも ▲ | `UsageTopBarView.compactRow` |
| 取得に失敗しても前回の値を出す（「下の値は 2 時間前のものです」） | 前回の値を 5 分で消さず、リセット時刻を過ぎるまで出し続ける。古さは帯と注記で示す。スマホへは古さを伝えられないので「取得できない」として送る | `UsageMonitor.resolvedUsage`・`syncedUsages` |

### 直していないもの

- C-39（Cursor が 0%）: 不具合ではなかった。Cursor の API が実際に Auto・API とも 100% 使用（「You've hit your usage limit」）を返している（2026-09-25 に確認）。
- ゲージのある段階の ▲: 見本のゲージ段階の例に ▲ が無く、「形（ゲージ・▲）で区別する」とあるので付けていない。
- ヘッダのチップのヘルプ文（ツールチップ）の注記は日本語のまま。ヘルプ文全体が前から日本語だけで、今回は触っていない。

### 検証

- `.claude/verify.sh` 合格。テストを足した（`UsageMonitorTests` の 2 時間前の値の保持・リセット後は保持しない・0% に直した値を保持しない・スマホへは取得できない扱い）。
- 独立レビュー（Codex）3 回と修正 2 回。英語表示で注記が日本語のまま出る点、スマホに古い値を正常値として送る点、リセット後に「残り 100%」を出し続ける点（2 経路）を直した。3 回目は高・中なし。
- Debug 版での確認（背面で起動し、アクセシビリティ経由の操作と撮影だけ）: ダークで文字だけの段階が「Cl 35 · Cx 61 · Cu ▲ 0%」になること。
- 実行できなかったもの: 「N 分前に取得 · 古い可能性」の実表示（Claude の値が 30 分より古くならなかった。文言はテストで確認）。取得失敗の帯の実表示（通信を止めていない）。

## F12 見送り分の再対応（3）: 設定（10 Settings）

### 対応表

| 見本の指示 | 内容 | 実装箇所 |
|---|---|---|
| 題名をタイトルバーの中央に（13pt semibold） | 窓の題名は読み上げと「ウインドウ」メニューのために残し、表示だけ隠して中央に描く。高さは実際のタイトルバーに合わせる。窓を出したあと SwiftUI が題名と形を戻すので、戻されたら当て直す（初回表示で左寄せ・白い帯のまま残っていたのも直った） | `SettingsView.body`・`SettingsWindowChrome` |
| 副ボタンの面 `--ctl`（ライト #FFFFFF・ダーク #4A4A4F）・角丸 5 | 設定の副ボタン・失効ボタンに設定用の面と角丸 5。ほかのダークテーマは窓の面から同じだけ持ち上げる | `DSColor.settingsControlBackground`・`DSButtonStyle(fill:cornerRadius:)` |
| C-53 フルアクセスの注記 | 見本の文「オンの間は、エージェントがファイルの変更やコマンドを確認なしで実行します。」に、エージェントごとの違いの注記（既存の文、凍結テストで固定）を続ける | `SettingsView.permissionFooter` |
| C-56 テーマ・アイコンは `role="radio"` | タイルの並びを読み上げでラジオグループ（「テーマ」「アプリアイコン」）にし、矢印キーで選択を動かす | `TileRadioGroup` |
| C-54「9月 20日にペアリング · 接続中」 | 認証の通った要求のトークンを端末に結び、最後の要求から 30 秒以内なら「接続中」（iPhone は開いている間 3 秒ごとに問い合わせる）。時刻は保存しない | `MobileDevicePresence`・`MobileDevicePairingRelay.notifySeen`・`MobileTokenViewModel.noteSeen` |

### 直していないもの

- 認証のたびに端末一覧を Keychain から読み直して一覧を更新するのは前からの挙動（レビューで中）。今回はそれを増やしていない（接続時刻は 10 秒に 1 回だけ進める）。
- C-55 のうち匿名の利用状況・トークン再発行: 機能が無いのでユーザーに相談する（決定記録どおり）。

### 検証

- `.claude/verify.sh` 合格。テストを足した（`MobileDevicePresenceTests`: 30 秒の境目、認証フックがトークンを接続の記録へ渡すこと）。
- 独立レビュー（Codex）2 回。題名の当て直しの KVO に問題なし。中は上の前からの挙動の 1 件だけ。
- Debug 版での確認（背面で起動し、アクセシビリティ経由の操作と撮影だけ）: ライト・日本語で初回表示から題名が中央（信号のボタンと同じ高さ）、題名の帯がタブ列と同じ面。テーマとアイコンが読み上げでラジオボタン、グループ名「テーマ」「アプリアイコン」。ダークで失効ボタンの面が #4A4A4F（撮影の画素で確認）。英語で題名「Agents」「Mobile」、注記「While on, agents change files and run commands without asking. Changes take effect…」、端末の行「Not connected」、グループ名「Theme」「App Icon」。
- 実行できなかったもの: 「接続中」の実表示（実機の iPhone をつないでいない。QR の読み取りも手元でできなかった）。矢印キーでの選択の移動（キー入力はユーザーの操作を奪うので行っていない）。VoiceOver での実際の読み上げ（アクセシビリティの役割は確認した）。

## F12 見送り分の再対応（4）: インスペクタとツール（07 Inspector and Tools）

### 対応表

| 見本の指示 | 内容 | 実装箇所 |
|---|---|---|
| C-42 ターミナルの「再起動」 | 子タブのターミナルは見出しを持たない（02 C5 の決定で外した）ので、表示メニューに「シェルを再起動」を置いた。共通ターミナルか、選択中セッションのターミナルの子タブが前面のときだけ有効。出力の購読はそのまま、新しいシェルを同じ表示に出す。再起動中・起動待ち中に閉じられたら起こし直さない | `UserTerminalController.restart`・`TerminalPanelSession.restart`・`ViewCommands`（`App/PhloxApp.swift`） |
| 02「ターミナルのタブを閉じるとシェルを終了する」 | 実機で、再起動・タブを閉じた後も対話 zsh が残るのを見つけた（SIGTERM を対話シェルは無視する）。ユーザー端末の終了は端末を閉じたときと同じ SIGHUP にした。エージェントの終了（SIGTERM）は変えていない | `PTYManagerProtocol.hangUp`・`Posix.hangUpGroup` |
| C-45（02「実行中のプロセスがあれば確認」） | ターミナルのタブを閉じるとき、シェルに子プロセスがあるか、シェルが `exec` で別のコマンドに置き換わっているときだけ確認を出す | `Posix.hasChildProcesses`・`PTYManager.spawnedImages`・`DashboardView.requestChildClose` |
| C-44 Git 操作中の表示（PhloxAux「コミットしています…」） | 操作中は「…」の帯に「コミットしています…／プッシュしています…／PR を作成しています…」、ボタンは「コミット中…」など。状態・エラー・プッシュ/PR 不可の理由をアプリ内の言語に合わせた | `GitCommitPanel.runningStatus`・`EditorPanelViewModel.runningOperation`・`localized` |
| B3 ブランチの切替失敗はピッカーの中に（凍結テストの変更は承認済み） | 失敗したらピッカーを開いたまま、下に「<ブランチ> に切り替えられません: <理由>」。理由が「:」で終わる git の文は次の行（ファイル名）を添える。成功で閉じる | `ComposerBranchPickerModel.finishCheckout`・`ComposerContextIndicator.branchPicker` |
| C-43 保存の競合で相手の名前（PhloxAux:158） | 開いてから同じファイルを書き換えた別のチャット型セッションが分かれば「開いてから別のセッション（アザミ · Codex）が書き換えました。…」。照合は保存と同じ Git のルート基準。その後にディスクが更新されていれば（5 秒の幅）分からないものとして従来の文 | `FileTabDocument.lastWriter`・`FileTabView` |
| D4 ファイルの編集欄に行番号（PhloxAux のコード行: 番号 28pt 右寄せ・淡色・左右 10） | NSTextView を包み、行番号の欄とカーソル行の塗りを付けた。折り返した行は 1 つの番号。スクロール・編集・テーマに追従 | `CodeTextEditor`（`LineNumberRuler`・`CurrentLineTextView`） |
| C-3 | 前のまとまりで実装済み（調査で確認） | — |

### 直していないもの

- ターミナルの見出し（文字サイズ・再起動のボタン）は子タブに出さない。02 C5 の「端末を全面に」と 07 D1 の見出しが食い違うため、02 の決定を優先し、再起動はメニューに置いた（レビューは見出しに置くよう中で指摘。見出しはどこにも表示されないので置いていない）。
- 相手の名前が分かるのはチャット型のファイル変更だけ。ターミナル型のエージェント・ターミナル・ほかのエディタでの書き換えは記録が無いので従来の文。
- チャットの変更の記録から 5 秒以内に別の手段で同じファイルが書き換えられると、チャットの名前を出してしまう（書き手の記録が無いので区別できない。レビューで中。`ponytail:` の注記どおり、必要なら保存の経路で書き手を記録する）。
- 子プロセスの有無で「実行中」を見るので、プロンプトの補助などの常駐の子を持つシェルでは毎回確認が出る（`ponytail:` の注記どおり）。
- 再起動後、前のシェルの出力は画面に残る（消さない）。
- メニューバーの文言がアプリ内言語ではなく OS の言語で出るのは前からの挙動。

### 検証

- 独立レビュー（Codex）3 回。高は 3 回目で 0 件。中の残りは上の 2 件（判断の記録）。
- 追加したテスト: `FileTabLastWriterTests`（Git ルートの下位フォルダから開いた保存競合で名前が出る・後から書き換えられたら出ない）、`UserTerminalControllerWhiteboxTests`（再起動で購読を保つ・再起動中／起動待ち中に閉じたら起こし直さない。後者は修正を外すと失敗することを確認）、`PTYManagerChildProcessTests`（実プロセスで、コマンド実行中・`exec` で置き換わったときに検出・対話 zsh が SIGHUP で終わる）、`AcceptanceBranchPickerPresentationTests`（承認済みの変更）。
- Debug 版での確認（背面で起動し、アクセシビリティ経由の操作と撮影だけ）: ライト・日本語とダーク・英語で行番号・スクロール追従・カーソル行の塗り。メニューから再起動して旧シェルが消え新しいシェルが出ること、タブを閉じるとシェルが終わること（プロセス一覧で確認）。検証用の /tmp のリポジトリで、ブランチ切替の失敗がピッカー内に英語で出て開いたままになること、コミット中の「Committing…」の帯とボタン、完了の「Committed a58b9a0.」、プッシュ/PR 不可の理由の英語。
- 実行できなかったもの: 実行中のコマンドがあるときの閉じる確認の実表示（キー入力はユーザーの操作を奪うので行っていない。単体と実プロセスのテストで確認）。保存競合のダイアログの実表示（テストのみ）。⌘S と取り消しの実操作（キー入力をしていない）。

## F12 見送り分の再対応（5）: worktree とダイアログ（08・09）

### 対応表

| 見本の指示 | 内容 | 実装箇所 |
|---|---|---|
| 08 F2・S5 worktree を作っている間の案内 | 画面から起動したセッションの worktree を作っている間だけ、作業ツリー自体のパスを出す。API・スマホからの起動のパスは出さない。パスが決まる前（置き場所だけの段階）は出さない | `DashboardViewModel.reportsWorktreeCreation`（`@TaskLocal`）・`worktreeCreationPath`・`DashboardView.worktreeProgressToast` |
| C-52（09 D2「…/hooks.json（Permission denied）」） | 片付けの警告に、残した場所と失敗の理由を等幅で出す。git の失敗は出力の 1 行目、ファイルの削除の失敗は OS の短い理由。worktree でない作業フォルダを消せなかったときも「作業フォルダを片付けられませんでした」を出し、消し残ったファイルを示す | `DashboardViewModel.cleanupFailureReason`・`WorkspaceCleanupWarning.workspaceRetained`・`CleanupWarningDialogText` |
| C-12（09 E4「既存の worktree を使う」） | worktree を作れなかった git の出力が「そのブランチは別の worktree で使用中」と言い、その場所がいまこのリポジトリの作業ツリーとして働いている（その場所で git が答える最上位と共通の .git が一致する）ときだけボタンを出す。押すとその worktree で隔離なしに起動する | `NewSessionCollisionGate.existingWorktree`・`SpawnGuardSheet.onUseWorktree` |
| D9 会話の書き出し（保存パネルの前段） | ⇧⌘E（メニュー）から書き出すとき、推論・コマンド出力・タイムスタンプを選ぶダイアログを先に出す。選んだ値は「書き出す…」を押したときだけ保存する。ヘッダのボタンからは C6 のポップオーバー（同じ 3 つのチェックボックスと「書き出す…」）が選択の段階を兼ねるので、ダイアログを重ねない | `ChatTranscriptExportAction`（`ExportOptionsForm`）・`DSDialogModal.run(content:)` |
| C-50（09 E2 作り直しの確認） | 前回 worktree で動いていたセッションを復元するとき、worktree が使えなければ作り直す前にたずねる（既定はキャンセル）。やめたらそのセッションは起動せず、一覧に失敗として残る。本文はブランチが残っているか・消えているかで 2 通り。登録だけ残ってブランチが消えた場合はブランチも作り直す | `SessionSpawnService.applyWorktreeIsolationOutcome`・`WorktreeRecreationDialog`・`CompositionRoot` |
| 復元で worktree をそのまま使うとき（レビューで高） | 登録だけ残って同じ場所が別のフォルダ・別のリポジトリに置き換わっていたら、そこを使わず起動しない（一覧には失敗として残る）。隔離をオフにした後の復元でも、後始末の対象として引き継がない。C-12 と同じ確かめ方 | `SessionSpawnService.applyWorktreeIsolationOutcome`（`.reuse`）・`prepareWorktreeIsolation` |
| C-27 権限の追加先の表示 | 決定どおり、プロトコルが情報をくれるか確かめた。Claude Code・Codex とも承認の要求に追加先（どの設定ファイルに書くか）を含めない。範囲は押したボタン（このターン／このセッション）で決まるので、追加先の行は出さない | —（判断の記録） |

### 直していないもの

- 見本 E2 の本文（「ブランチが削除されている」）は、作り直しの実際の条件（フォルダが無い／ブランチも無い）と合わないので、起きていることを書く 2 通りの文にした。
- 画面からの起動が重なったら、先に作り始めたほうのパスを案内に出す（`ponytail:` の注記どおり。起動ごとに出し分けるなら起動の識別子を案内まで渡す）。
- 消し残ったファイルは「作業フォルダの中で最初に見つかった、消えていないファイル」を出す。複数残ったときは 1 つだけで、失敗したファイルと違うことがある（OS のエラーはフォルダしか指さない。`ponytail:` の注記どおり）。
- 隔離オフで作ったセッションを、あとで隔離オンにしたプロジェクトで復元すると、たずねずに新しい worktree を作る（前からの挙動。「前回の worktree」が無いので確認の対象にしない）。
- 復元でそのまま使う worktree は、同じリポジトリの作業ツリーかどうかまでを確かめ、ブランチは確かめない。エージェントがその worktree の中でブランチを切り替えた正当な場合を壊さないため。残る穴: アプリを閉じている間に、ユーザーが Phlox 専用の場所（workspaces/<セッション>）の worktree を手で消し、同じ場所に別ブランチで作り直すと、復元はそれを使い、セッションを消すと後始末の対象になる（汚れていれば消さずに警告）。変更前からある挙動。塞ぐには作成時に worktree 固有の識別子を保存して復元時に照合する仕組みが要り、このまとまりの範囲を超えるので入れていない（レビューは高で指摘）。
- まとめ通知の件数を、表示済みの通知で音やバナーを出し直さずに書き換えることはできない（macOS の通知 API に、表示済みの通知の内容を変える公開の手段が無い）。まだ表示されていないものは同じ識別子で置き換わる。

### 検証

- 独立レビュー（Codex）9 回。最後の高 1 件は上の「残る穴」（変更前からの挙動）。ほかの高・中は無し。
- 検証ゲート `bash .claude/verify.sh` が通った（DesignSystem・AgentDomain・SessionFeature・DashboardFeature のテストとアプリのビルド）。
- 追加したテスト: `CleanupFailureReasonTests`（git の出力の 1 行目・理由の付け方・書き込めないフォルダを含む作業フォルダを消したときにファイル名と「Permission denied」が出る）、`WorktreeIsolationSpawnTests` に 7 本（既存の worktree はこのリポジトリの作業ツリーだけ見つけ、`.git` ファイルだけの別フォルダ・登録を残して別のリポジトリに置き換わった場所では出さない・作成中だけパスが出て終わると消える・API からの起動のパスは出さない・復元で作り直す前にたずねる 4 通り・登録だけ残ってブランチが消えたとき「ブランチが無い」ほうを出し作り直しでブランチも作る・隔離オフで作ったセッションではたずねない・別のリポジトリに置き換わった場所を復元で使わない）。後ろの 4 つは、修正を外すと失敗することを確かめた。
- 画面での確認はしていない: D9・E2（2 通り）・作業フォルダの片付け警告のダイアログ、worktree の案内。Debug 版のモーダルはユーザーが使っている画面の前に出るおそれがあるので出していない。文言は英語訳を `Localizable.xcstrings` に入れた。

## F12 見送り分の再対応（6）: 通知と起動（11 Notifications and Startup・10 Settings）

### 対応表

| 見本の指示 | 内容 | 実装箇所 |
|---|---|---|
| C-64（11 I3 移行の失敗で止める） | 旧データを移すとき、`projects.json`・`sessions.json` が起動後の読み込みと同じ復号で読めなければ、移行先を作らず旧データを残したまま起動を止める。確かめるのは移し終えた一時フォルダの中身（コピーの途中で旧ファイルが変わっても、相対リンクの先が移らなくても、起動後に読むものを見る）。あわせて、起動後の読み込みは版番号の無いファイルを 1 とみなして読む（これまでは壊れた扱いで退避して空にしていた）。理由の文は起動画面の「AppSupportMigrator: 」の後ろに続く形 | `AppSupportMigrator.validateJSON`・`JSONSessionStore`／`JSONProjectStore`（`canRead`・版番号の既定） |
| C-61（10 Settings「バッジに出す数」） | 通知の設定に「Dock」を足し、対応待ちの数（既定）か未読の完了の数を選べる。変えるとすぐ Dock に反映 | `NotificationSettings.dockBadgeCount`・`DockBadge.label(_:attentionCount:unseenCompletionCount:)`・`AppDelegate.applyDockBadge`・`SettingsView` |
| C-55（10 Settings L3「プッシュ通知」） | モバイルの設定で、つないだ端末があるとき「iPhone に通知を送る」を出す。オフなら通知も Live Activity も送らない（送信の入口で止める）。送る鍵（APNs）が無いときは「オンでも送信されません」と琥珀の文字で添える | `APNsNotificationBridge.notify`・`isSendingConfigured`・`MobileTokenViewModel.isPushSendingConfigured`・`SettingsView.MobileTokenSection` |
| C-62・B5（11「同じ文言を iOS 側にも渡す」・質問を承認と分ける） | スマホへ、完了・承認待ち・質問・エラー・無応答・終了をそれぞれの種類で送る（これまでは完了と承認待ちの 2 つだけで、質問も承認待ちとして送っていた）。本文は種類の言葉（「質問があります」「セッションが終了しました · exit 1」など）。iOS は種類を名前つきで読み、Live Activity の記号を種類ごとに出す（短い状態は Done／End／Error／Wait の 4 通り） | `RemoteSessionNotification`・`RemoteSessionNotifier.notify`・`APNsNotificationBridge.NotificationEvent`・`PhloxPushPayload.EventType`・`SessionLiveActivity` |
| C-60（11「終了」） | ターミナル型のプロセスが 0 以外の終了コードで終わったら「セッションが終了しました: {名前}」、本文「exit 1」を出す（実行中でなくても）。スマホにも送る | `SessionViewModel.startExitTask`・`SessionNotificationText.Kind.exited`・`SessionCompletionNotifier.notifyExited` |

### 直していないもの

- スマホへの通知に、承認の対象・質問文・エラー文・直近の動作は入れない（ユーザーの判断。通知は Apple のサーバーを経由し、リモート通知に本文の中身を含めない既存の決まりを守る）。
- 匿名の利用状況の送信とトークンの再発行は置かない（ユーザーの判断。見本でも推測で、裏付けの機能が無い）。
- スイッチの名前は見本の「承認待ちを iPhone に送る」ではなく「iPhone に通知を送る」。承認待ち以外も送るようになったため。
- 実行中に終了コード 0 で終わったときは、これまでどおり完了として知らせる。見本の「0 のときは通知しない」は「終了」の通知の話と読み、既存のテスト（`notificationGap_ptyProcessExit_firesSessionCompleted`）が固定している意図的な挙動を残した。
- チャット型は終了コードを受け取れない（プロセスの終わりを扱う層が終了コードを捨てている）ので「終了」の通知の対象外。C-17（終了コードと再開ボタン）で経路を作るときに合わせる。→（7）で経路を作り、チャット型も 0 以外の終了で「終了」を通知するようにした。
- 移行の検査は起動後の読み込みと同じ復号で行う。セッションは 1 件ずつ読めないものを起動後の読み込みが捨てて退避するので、それだけでは止めない。
- 更新用のトークンが無いときの完了・終了は、完了済みの Live Activity を新しく出す（60 秒後に古い扱いにするだけで、消える時刻は OS が決める）。最初からの意図的な設計（`completionWithoutExistingActivityStartsAlreadyCompletedLiveActivity` が固定）で、終了も同じ扱いにした（レビューは中で「終わった知らせで始めない」よう指摘）。
- 設定の保存先: 新しく足した「バッジに出す数」「iPhone に通知を送る」は、読む側と同じ保存先（`PHLOX_DEFAULTS_SUITE` を指定した隔離起動ではその保存先）に書く。既存の「バナーで知らせる」「完了サウンド」は標準の保存先に書いたまま（前からの挙動）。
- まとめ通知の件数を、表示済みの通知で音やバナーを出し直さずに書き換えることはできない（上の（5）に記載）。

### 検証

- 追加したテスト: `AppSupportMigratorTests`（壊れた JSON・一覧が読めない 3 通り・版番号が読めない・プロジェクトの 1 件が読めない・壊れた JSON を指すリンク・移らない先を指す相対リンクで止まり移行先を作らない、移る先を指す相対リンクは通す）、`JSONSessionStoreTests`・`JSONProjectStoreTests`（版番号の無いファイルを読み、退避しない）、`DockBadgeCountSettingTests`（選んだ数を出す・既定は対応待ち）、`APNsNotificationBridgeTests.turnedOffInSettingsSendsNothing`、`LiveActivityBridgeTests.eachKindIsSentWithItsOwnTypeAndWords`（4 種類の type・本文・Live Activity の終わり方と残す時間）、`remoteNotifier_defaultRoutesKindsToTheTwoLegacyCalls`、`chatRemoteNotifier_questionIsSentAsAQuestion`、`notificationGap_ptyNonZeroExit_sendsTheExitCodeEvenWhenIdle`、iOS の `decodesEveryDesktopNotificationKind`。
- 通ったもの: 検証ゲート `bash .claude/verify.sh`、AppBootstrap 163 件、MessageStore 42 件、iOS PhloxKit（Swift Testing 698 件と XCTest。終了コード 0）、アプリのビルド。
- 見つけて直した前からの失敗: iOS の `TokensTests.testReExportsStatusVocabulary` が、前のまとまり（4a58aa9、12 Design System の語彙）で「完了 (0)」→「完了」に変えたのに古い期待値のままで落ちていた。iOS のテストはゲートに入っておらず、XCTest 側の失敗が Swift Testing の要約に隠れていた。期待値を見本の語彙に合わせた。
- Debug 版での確認（背面・撮影だけ）: ダーク・英語で通知の設定に「Dock / Badge shows / Sessions that need you」が出ること。
- 確認できなかったもの: iOS のウィジェット（`SessionLiveActivity`）のビルド（プロジェクトの生成に使う xcodegen が入っておらず、ツールは入れない約束のため）。モバイルの設定の「プッシュ通知」の表示（つないだ端末が要り、実機が無い）。Dock のバッジの見た目（画面全体を撮ることになるので撮っていない）。

## F12 見送り分の再対応（7）: 会話（04 Session Chat・PhloxChat）

### 対応表

| 見本の指示 | 内容 | 実装箇所 |
|---|---|---|
| B2（会話の項目の間隔） | 会話の項目どうしの間隔を種類によらず 14pt にする（先頭は 0）。接続中・圧縮中・思考中の行、Codex のプランのカード、「さらに読み込む」との間も同じ（ユーザー決定。凍結テストの変更は承認済み） | `TranscriptTypography.itemGap`・`gap(after:before:)`・`ChatTranscriptView` |
| B6（見出しの高さ） | 会話の見出しとサブエージェント欄の見出しの共有の高さを 56pt に（見本はどちらも 56px。承認済み）。会話の見出しはこの定数を使う | `SubAgentSplitLayout.headerHeight`・`ChatSessionHeader.height` |
| C-16（04「カードの既定の開き方」: タスクリスト） | いちばん新しいタスクリストだけ既定で開く。会話に置かれるタスクリストは常に 1 枚（差し替え）なので、いつも開く | `TranscriptItemPresentation.taskList(isLatest:)`・`TaskListCell` |
| C-22（同: コマンド単体・04 B4） | 失敗（exit ≠ 0）したコマンド単体だけ既定で開く。コマンドグループは実行中だけ開くまま。Codex は完了時の `exitCode`（出力は `aggregatedOutput`）を Claude と同じ「Exit code N」行にして先頭に置き、出力に別の値の行があれば構造化された値を優先する | `TranscriptItemPresentation.command(hasFailed:)`・`CommandExecutionCell`・`ChatSessionViewModel.chatItem(from:)` |
| C-17（04 B3・PhloxChat の showEnded） | エージェントのプロセスが自分で終わったら、入力欄の代わりに「セッションは終了しました（exit N）。会話は保存されています。」と「この会話から再開」を出す（単体表示・グリッドとも）。見出しは 0 なら「完了 · exit 0」。0 以外は PTY と同じくエラーにして「終了」を通知する。終わったときに待っていた質問・承認は答えられないので片付ける（承認はプロセス側へ否認で決着させ、終わった後に届いた承認・質問は出さない）。再開は起動時の復元と同じ経路で新しいプロセスの VM を作り、会話を読み込み終えてから同じ位置のノードを差し替える（続けて押しても 2 つ目は作らない。開き直せなければ差し替えず、終わった会話に理由を出して再開ボタンを残す。開き直している間に閉じられたら、新しいプロセスは止める）。終了コードは Claude（`LineDelimitedProcessTransport`）と Codex（`ProcessTransport`）の終了時に記録し、`NormalizedChatEvent.processExited` で渡す | `ChatProcessEndedStrip`・`ChatSessionViewModel.processExit`／`resumeConversationHandler`・`DashboardViewModel.resumeEndedChatSession`・`SessionRestoreCoordinator.resumeChatSession`・`ClaudeChatClient.yieldProcessExited`・`CodexStructuredAgentClient.bridgeDidFinish` |
| C-21（PhloxChat の historyCards） | 履歴カードの 2 行目を「最後: {最後の発言}」、右下を「{件数} 件 · {ブランチ}」にする。一覧を出したあと、裏で 1 件ずつ会話を読んで埋める（読み終えるまではこれまでどおりプロジェクト名とブランチ）。読み上げにも足す | `ChatHistorySummary`・`ChatSessionViewModel.historySummaries`・`ChatHistoryStartView` |
| 見送り分（復元後の表示） | 再起動して復元しても、返信の下のトークン内訳、「N分前に応答」、サブエージェントの記録（出力ファイルの場所）を同じに出す。本文と同じ保存の列で、本文の後に別ファイル（`<id>.display.json`）へ書く。本文の書き込みに失敗したあとは書かない。動いていたサブエージェントは失敗として戻す | `ChatDisplayState`・`TranscriptStore.loadDisplayState`／`saveDisplayState`・`TranscriptPersistenceQueue.enqueueDisplayState`・`ChatSubAgentModel.restore` |

### 直していないもの

- Claude は中断で CLI を止め、次の送信で `--resume` して起動し直す設計なので、中断した世代の終了では「終了」を出さない。`close()` で受信を打ち切ったときと、自己修復で新しいプロセスが起動できたとき（ターンの再送だけ失敗しても）と、終了コードを待つ間に次の送信で新しいプロセスが起動したときも出さない。
- 終了の前にエラーが届き、それを通知済みなら（実行中に止まった場合）、「終了」を重ねて通知しない（同じ出来事で 2 回鳴らさない）。終了コードは入力欄の代わりの帯に出る。エラーが通知されていなければ終了コードつきで通知する。
- 終了コードが取れないときは完了にせずエラー（「process exited」）とする。
- Cursor はコマンドごとの終了コードを持たないので、失敗したコマンドを開けない（Cursor は 1 回ごとに起動する作りで、プロセスの終了は「終了」の対象外）。
- 履歴カードの件数は、再開時に読み込む上限（新しい方から 500 件）までを数え、届いたら「500 件以上」。Codex の履歴はファイル末尾の 4MB だけを読むので、それより長い会話の件数は末尾の分になる（上限は `ponytail:` 注記に明記）。
- あわせて直した前からの不具合: Codex の履歴はファイルの先頭 4MB・先頭 500 件を読んでいたため、長い会話では再開時の表示も最後の発言も古かった。Claude と同じく新しい方を残す。
- 画面で見つけた前からの挙動: Codex のチャットは、復元後に待機中でもプロセスが終わると「Codex app-server process exited before the turn completed」のエラーが出る（復元した会話に終わっていないターンが残っている扱い）。今回は触っていない。
- 履歴カードの日時（「今日 16:52」）と題の既定値（「作業名なし」）は英語表示でも日本語のまま（前からの挙動）。

### 検証

- 追加したテスト: `CardDefaultExpansionTests`（失敗したコマンド単体だけ開く・グループは開かない・最新のタスクリストだけ開く）、`notificationGap_chatProcess*`（0 以外の終了・0 の終了・通知済みのエラーの後・未通知のエラーの後・終了コード不明・承認待ちの間の終了・終了より後に届いた承認）、`processTransportRecordsTheExitCodeBeforeTheLinesFinish`（StructuredChatKit・CodexAppServerKit）と `processTransportReportsASignalExitAs128PlusTheSignal`、`idleProcessExitYieldsTheExitCode`・`interruptEndingTheTransportDoesNotYieldProcessExited`・`failedSelfHealYieldsTheOriginalExitCode`・`selfHealWhoseReplayFailsDoesNotYieldProcessExited`・`exitOfTheOldProcessIsNotReportedAfterTheNextTurnRespawns`（ClaudeAgentKit）、`resumeEndedChatSession_replacesTheNodeInPlaceAndResumesTheSameConversation`・`resumeEndedChatSession_ignoresASecondPressWhileResuming`・`resumeEndedChatSession_keepsTheEndedSessionWhenResumingFails`・`resumeEndedChatSession_stopsTheNewProcessWhenTheSessionIsClosedMeanwhile`、`ChatHistorySummaryTests`、`codexSessionHistory_loadTranscriptKeepsTheNewestItems`、`codex_failedCommandCompletionCarriesTheExitCodeAndAggregatedOutput`・`codex_structuredExitCodeWinsOverAnExitCodeLineInTheOutput`・`codex_structuredZeroExitCodeWinsOverAFailureLineInTheOutput`、`chatDisplayState_survivesRestore`・`chatDisplayState_runningSubAgentIsRestoredAsFailed`、`displayStateIsSkippedAfterAFailedTranscriptWriteAndResumesAfterASuccess`。主なものは、直した箇所を外すと落ちることを確かめた。
- 変えた凍結テスト（承認済み）: `AcceptanceTranscriptTypographyTests`・`AcceptanceTranscriptTypographyIntegrationTests`（間隔を一律 14）、`AcceptanceSingleHeaderLayoutTests`・`ChatSessionHeaderWhiteboxTests`（見出し 56）。
- 通ったもの: 検証ゲート `bash .claude/verify.sh`、ゲートに入っていない StructuredChatKit 28 件・ClaudeAgentKit 173 件・CodexAppServerKit 100 件、アプリのビルド。
- Debug 版での確認（背面・撮影だけ。ダーク・英語）: 会話の間隔と見出しの高さ。Codex のチャットでプロセス（Debug 版の子）を止めると入力欄の代わりに終了の帯と「Resume this conversation」が出て、押すと新しいプロセスで同じ会話に戻り末尾に寄ること（最初は先頭のまま表示されたので、読み込み後に差し替えるよう直した）。新しい Claude のチャットの履歴カードに「Last: …」と「4 messages · feature/…」が出ること。
- 独立レビュー（読み取りのみ）: 11 回繰り返し、最後は高・中なし。残した低は 4MB を超える Codex 履歴の件数（上記）。
- 確認できなかったもの: 「完了 · exit 0」の見出し（止めた Codex は先にエラーが出るため、画面では 0 の完了にならなかった。テストでは確認）。ライト表示での終了の帯。
