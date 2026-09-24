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
