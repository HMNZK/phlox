---
status: accepted
last-verified: 2026-08-01
---

# ADR 0149: ユーザーターミナルはセッション非依存・cwd はホーム固定・シェルは閉じても保持

> **このファイルの役割**: パネル用ユーザーターミナル（`UserTerminalController`）の cwd・
> セッションとの関係・閉時の挙動・アプリ終了時の後始末順序の決定（ゲート①決定）。
> **書かないもの**: パネル容器の選択（→ [ADR 0148](0148-terminal-editor-panel-container-drawer.md)）、
> PTY spawn 時の fd 継承対策（→ [ADR 0151](0151-pty-spawn-fd-hygiene.md)）。

## 文脈

phase0 の仮定Bは「ターミナルの cwd は選択中セッションのプロジェクトディレクトリ」だったが、
確定が必要な未知点として残していた（未知③: パネル用 PTY を「セッション」として登録するか、
独立管理するかという副作用の懸念も含む）。ユーザー自身が手でコマンドを打つための汎用ターミナルと、
エージェントが動かすセッションを混同すると、一覧・復元・通知に意図しない副作用が出る。

## 決定

1. **ユーザーターミナルはセッション（エージェント）と完全に無関係の独立機能**とする。
   `UserTerminalController` は `DashboardViewModel` のセッション一覧・復元・通知の対象に登録しない。
2. **cwd は常にホームディレクトリ固定**（`FileManager.default.homeDirectoryForCurrentUser.path`）。
   選択中セッションのプロジェクトへの追従はしない（仮定Bを置換）。
3. **パネルを閉じてもシェルはバックグラウンドで保持する**。`TerminalPanelSession`
   （`UserTerminalController` と `TerminalCoordinator` の所有者）は `DashboardView` の
   drawer コンテンツではなく、`PhloxApp` の `@State` として保持され、ドロワーの開閉に
   ライフサイクルが連動しない。再度パネルを開くと、SwiftTerm のバッファに蓄積済みの
   画面（scrollback）ごと復帰する。
4. **アプリ終了時にのみ後始末する**。`AppDelegate.applicationShouldTerminate` から
   `shutdownUserTerminal()` を呼び、`UserTerminalController.shutdown()` でシェルを終了させる。

## 終了時の後始末順序

`AppDelegate.swift`（extension）の `applicationShouldTerminate(_:)` は次の 2 系統を並行実行し、
両方の完了を待ってから `reply(toApplicationShouldTerminate: true)` を返す（`.terminateLater`）。

1. **PTY 系統**（順次）: `shutdownUserTerminal()`（= `UserTerminalController.shutdown()`）を
   待ってから、既存の `PTYManager.terminateAllAndWait(timeout:)`
   （エージェントセッションの PTY 群を一括終了。ADR 0009）を呼ぶ。
2. **transcript flush 系統**: 全チャットセッションの `flushTranscriptNow()` を並行実行する
   （[ADR 0110](0110-midturn-flush-and-termination-race.md) の既存メカニズム）。

シグナル経路（SIGTERM/SIGINT）と多重実行しないよう `cleanupGuard.beginCleanup()` で
「高々 1 回」を担保する（既存の仕組みを流用）。

## 棄却した選択肢

- **cwd をセッションの作業ディレクトリに連動させる**（phase0 の仮定B）: ユーザーが「独立した
  作業用シェル」を期待するユースケースと衝突するため、ゲート①でユーザーが不要と裁定。
- **パネルを閉じたらシェルを破棄する**: シェル内の作業状態（実行中コマンド・履歴・cd 先）が
  パネル開閉のたびに失われるのは実用に反するとして不採用。

## 結果

- `UserTerminalController` は多重 spawn 防止（`ensureStarted()` の起動中ガード）・自然終了検知
  （exit stream 監視で `isRunning` を false にし、再 `ensureStarted()` で新しい `sessionID` を
  払い出す）・購読者の世代分離（`spawnGeneration` によるガードで旧世代の出力が新セッションの
  購読者に混入しない）を実装する。
- 回帰保護: `AcceptanceUserTerminalTests`（task-1）・`UserTerminalControllerWhiteboxTests`
  （多重 spawn・自然終了・世代分離・drain 待ちの白箱テスト）。
