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
