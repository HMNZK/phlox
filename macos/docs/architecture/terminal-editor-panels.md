---
status: active
last-verified: 2026-08-01
---

# ターミナル／エディタパネルの現行構成

> **このファイルの役割**: ターミナルパネル・エディタパネルを構成するコンポーネントと、
> ドロワー・ホットキーへの配線、アプリ終了時の後始末の**現行構造**。
> **書かないもの**: なぜこの容器・この仕様にしたか（→ [ADR 0148](../adr/0148-terminal-editor-panel-container-drawer.md)〜
> [ADR 0151](../adr/0151-pty-spawn-fd-hygiene.md)）、満たすべき要件（→ [specs/terminal-editor-panels.md](../specs/terminal-editor-panels.md)）。

## コンポーネント

| 層 | 型 / 関数（パッケージ・ファイル） | 役割 |
|---|---|---|
| ルーティング | `AppRouter.terminalPanelVisible` / `.editorPanelVisible` / `toggleTerminalPanel()` / `toggleEditorPanel()`（DashboardFeature/Router） | パネルの表示状態と開閉トグル |
| PTY ライフサイクル | `UserTerminalController`（DashboardFeature/UserTerminal、`@MainActor`） | ホームディレクトリを cwd に `PTYManagerProtocol` 経由でシェルを起動・保持・shutdown。多重 spawn 防止・自然終了検知・`spawnGeneration` による購読者の世代分離・`requestedSize` によるサイズ保留（起動前 resize の反映） |
| パネル寿命の所有者 | `TerminalPanelSession`（DashboardFeature/UserTerminal/TerminalPanelView.swift） | `UserTerminalController` と `TerminalUI.TerminalCoordinator` を束ね、ドロワーの開閉と無関係に `PhloxApp` の `@State` として保持される |
| ターミナル表示 | `TerminalPanelView`（同ファイル） | `TerminalCoordinator` を `TerminalUI.TerminalView`（SwiftTerm 表示）へ橋渡しする、容器非依存の View |
| git 読み書き | `WorkingTreeService`（DashboardFeature/WorkingTree、`actor`） | `/usr/bin/git`（`--no-optional-locks` 付き）をラップし、`isGitRepository()` / `changes()` / `detail(for:)` / `fileContents(_:)` / `save(path:content:expectedDiskContent:)` を提供 |
| git 値型 | `WorkingTreeChange` / `WorkingTreeDetail` / `WorkingTreeSaveOutcome`（DashboardFeature/WorkingTree/WorkingTreeTypes.swift） | 変更エントリ（path/kind/isBinary）・詳細（diff/untrackedContent/binary）・保存結果（saved/conflict） |
| エディタ VM | `EditorPanelViewModel`（DashboardFeature/Editor、`@MainActor @Observable`） | `listState`（noProject/notARepository/ready）・`changes`・`selectedPath`・`detail`・`draft`・`isDirty` を保持し、`refresh()` / `select(_:)` / `save()` / `overwrite()` を提供。競合検出は「選択時点でロードしたディスク内容」を基準にする |
| エディタ内部レイアウト | `EditorPanelLayout`（DashboardFeature/Editor/EditorPanelView.swift、SwiftUI 非依存の純粋 enum） | ドロワー幅から `.split`（変更リスト＋詳細を左右分割。内在最小幅 541pt）／`.stacked`（縦積み）を決める |
| エディタ表示 | `EditorPanelView`（同ファイル） | 変更一覧・diff/内容プレビュー（`ChatCodeHighlighter.highlight` で構文ハイライト。SessionFeature の `ChatCodeBlock.swift` を共有）・`TextEditor` での編集・保存・競合アラートを持つ、容器非依存の View |
| ドロワー幅決定 | `PanelDrawerLayout`（DashboardFeature/Dashboard、SwiftUI 非依存の純粋 enum） | `clamped(width:availableWidth:)` / `proposedWidth(startWidth:translation:availableWidth:)`。既定幅 420pt・最小幅 280pt |
| ドロワー統合 | `DashboardView`（DashboardFeature/Dashboard） | 本文 `HStack` の一部としてドロワーを配置（レイアウトフロー内）。両パネル可視時は `VSplitView` で縦積み。分割線ハンドルは overlay チェーンの最後に配置し、ドラッグ中はゴースト線のみ更新（`onEnded` で `storedDrawerWidth`（`@AppStorage`）を確定）。`updateEditorPanelProject()` がセッション選択の変化に応じて `EditorPanelViewModel` を作り直す |
| トップバー | `DashboardTopBarControls` / `TrailingTopBarLayout`（DashboardFeature/Dashboard） | `usageAvailableWidth` はウィンドウ全幅（`geometry.size.width`）基準で、ドロワー幅を差し引かない |
| ホットキー配線 | `TerminalPanelCommands` / `EditorPanelCommands`（App/PhloxApp.swift） | ⌘⌥T / ⌘⌥E の `CommandGroup(after: .sidebar)`。`router.toggleTerminalPanel()` / `toggleEditorPanel()` を呼ぶ |
| PTY spawn 起動 | `makeTerminalPanelSession(environment:)`（App/PhloxApp.swift） | `UserTerminalController` をホーム cwd・ログインシェル（`loginShellPath()`）で構築し、`AppDelegate.userTerminalController` へも渡す |
| 終了処理 | `AppDelegate`（App/AppDelegate.swift、extension） | `applicationShouldTerminate` から `shutdownUserTerminal()` → `PTYManager.terminateAllAndWait` を待つ Task と、全チャットセッションの `flushTranscriptNow()` を待つ Task を並行実行し、両方の完了後に reply する（[ADR 0110](../adr/0110-midturn-flush-and-termination-race.md)・[ADR 0149](../adr/0149-user-terminal-lifecycle.md)） |
| fd 衛生 | `Posix.spawn`（PTYKit/Sources/PTYKit/Posix.swift） | `posix_spawnattr_setflags` に `POSIX_SPAWN_CLOEXEC_DEFAULT` を含め、`file_actions` で明示 dup2 されていない fd を子へ継承しない（[ADR 0151](../adr/0151-pty-spawn-fd-hygiene.md)） |

## データフロー（ターミナル）

1. `PhloxApp` が起動時に `TerminalPanelSession` を 1 つ生成し、`@State` として保持（`AppDelegate` にも
   `userTerminalController` として共有）。
2. `TerminalPanelSession.init` が `TerminalCoordinator.onInput` / `.onResize` を
   `UserTerminalController.send(_:)` / `.resize(cols:rows:)` に配線し、`makeOutputStream()` を
   継続的に消費して `TerminalCoordinator.feed(_:)` へ流す（表示器が閉じていても購読は継続）。
3. `TerminalPanelView.task` が初回表示・自然終了後の再表示のときに `TerminalPanelSession.ensureStarted()`
   を呼び、`UserTerminalController.ensureStarted()` が未起動ならホーム cwd でシェルを spawn する。
4. ドロワーを閉じても `TerminalPanelSession` は破棄されない（`DashboardView` はドロワー可視時にだけ
   `TerminalPanelView` をレンダリングするが、`panel` そのものの所有者は `PhloxApp`）。

## データフロー（エディタ）

1. `DashboardView` はセッション選択・プロジェクト一覧の変化を `updateEditorPanelProject()` で監視し、
   対象プロジェクトが変わったら `WorkingTreeService(repositoryRoot:)` を注入した新しい
   `EditorPanelViewModel` を作る（未選択時は `service: nil`）。
2. `EditorPanelView` はドロワー幅（`GeometryReader`）を `EditorPanelLayout.mode(forWidth:)` に通し、
   `.split`（`HSplitView`）／`.stacked`（`VSplitView`）を切り替えて変更一覧と詳細ペインを配置する。
3. Refresh ボタン → `viewModel.refresh()` → `WorkingTreeService.changes()`。ファイル選択 →
   `viewModel.select(_:)` → `WorkingTreeService.detail(for:)` + `fileContents(_:)`（追跡ファイルの
   場合、diff 表示と同時に本文を読み込んで `draft` へロードする）。
4. 保存 → `viewModel.save()` → `WorkingTreeService.save(path:content:expectedDiskContent:)`。
   `.conflict` が返ると View がアラートを出し、ユーザーが選べば `viewModel.overwrite()` で
   `expectedDiskContent: nil` の無条件上書きを行う。

## テスト

| ファイル | 固定している性質 |
|---|---|
| `AcceptancePanelRouterTests` | `AppRouter` のパネルフラグ・トグル |
| `AcceptanceUserTerminalTests` / `UserTerminalControllerWhiteboxTests` | PTY 起動の冪等性・入出力・自然終了→再起動・世代分離・drain 待ち・shutdown 冪等 |
| `AcceptanceWorkingTreeTests` / `WorkingTreeServiceWhiteboxTests` | 変更一覧・diff・保存・競合検出・リネーム/非 ASCII パス・巨大 stderr 耐性 |
| `AcceptanceTerminalPanelWiringTests` / `TerminalPanelViewWhiteboxTests` | ホットキー配線・ドロワーがオーバーレイでないこと・resize の3状態化 |
| `AcceptanceEditorPanelVMTests` / `EditorPanelVMWhiteboxTests` | VM の一覧/選択/編集/保存/競合フロー |
| `AcceptancePanelIntegrationTests` / `PanelIntegrationWhiteboxTests` | 確定容器への統合・プロトタイプ撤去・ドロワー幅クランプ/ドラッグ・トップバー独立 |
| `PosixSpawnCloexecTests`（PTYKit） | spawn した子が無関係な fd を継承しないこと |
| `PanelUITests`（XCUITest） | ⌘⌥T/⌘⌥E の実出現・消滅（accessibilityIdentifier） |
