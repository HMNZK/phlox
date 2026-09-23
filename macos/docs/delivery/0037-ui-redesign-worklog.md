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
