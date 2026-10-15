---
status: active
last-verified: 2026-10-15
---

# チャットモードのオーケストレーション（現状仕様）

> **このファイルの役割**: チャットモード（`SessionBackend.appServer`）のセッションが `$PHLOX_CLI` で他エージェントを spawn/send/wait するとき、spawn backend 継承・wait 完了検知が「今どう動いているか」（旧「ガイド配信」は ADR 0035 で廃止）。
> **書かないもの**: なぜこの設計か（→ ADR 0026）、ターミナルモード（PTY）や Claude チャットのプロセスライフサイクル（→ architecture/claude-chat-session-lifecycle.md）。

## 1. オーケストレーションガイドの配信 → 廃止（ADR 0035）

かつてチャット各 kind に `OrchestrationGuide.guideText` を native チャネル（Claude=`--append-system-prompt` / Codex=`developerInstructions` / Cursor=`.cursor/rules`）で毎ターン届けていたが、**この自動注入は全種別で廃止した（ADR 0035）**。`OrchestrationGuide`・`PHLOX_ORCHESTRATION_GUIDE` env・`install()` はコードから撤去済み。オーケストレーションの基本手順（spawn/send/wait/kill）は Claude の `/phlox-cli` スキル（明示参照）に一元化された。チャットモードのセッションで spawn/send/wait を行うときは同スキルを参照する。以降の §2・§3（spawn backend 継承・wait 完了検知）は現行仕様として有効。

## 2. spawn の backend 継承

`DashboardViewModel.spawnNewSession` は子の backend を親（`from`）から継承する（`Dashboard/DashboardViewModel.swift`）:

```
resolvedBackend =
  親(from)が appServer セッション かつ 子kindが structured chat 対応 → .appServer
  それ以外 → 要求どおりの backend（既定 .pty）
```

昇格のみ（appServer へ）で降格しない。`resolvedBackend` は spawn の guard・plan 生成・pty/appServer 分岐・永続化（`PersistedSessionDescriptor.backend`）すべてで使われる。CLI は backend を送らず、ControlServer は省略時 `.pty` を既定にする（この既定は継承ロジックが親ありのとき上書きする）。

## 2b. spawn の作業ディレクトリ解決（workingDirectory）

`POST /sessions` は省略可能な `workingDirectory`（絶対パス）を受け、CLI は `phlox spawn --kind <k> --dir <path>` で送る（省略時はフィールド自体を送らない）。解決順（ADR 0061）:

```
workingDirectory 指定あり → その値を verbatim に使用（worktree 等への着地。pty/appServer 共通）
指定なし               → 親(from)の projectID を継承 → project.directoryPath
どちらも無い           → Phlox 管理ワークスペース（sessionWorkspaceDirectory）
```

- 検証は `ControlActionHandler.handleSpawn` の**1箇所のみ**: 絶対パス・存在・ディレクトリ（symlink-to-dir 許容）。不正・空文字は 400 で spawn 不発火（黙示フォールバックしない）。パース層（ControlServer）と VM 層は検証しない——VM 層に置くと、保存済みディレクトリが消えた場合にセッション復元（`SessionRestoreCoordinator` が同じ `workingDirectoryOverride` を使う）が壊れるため。
- 解決された作業ディレクトリは `PersistedSessionDescriptor.workingDirectory` に永続化され、再起動時の復元でそのまま再利用される。
- 契約の凍結テスト: `SpawnWorkingDirectoryAcceptanceTests`（ControlServer）/ `SpawnWorkingDirectoryHandlerAcceptanceTests`（AppBootstrap）。

## 2c. 新規チャットの worktree の起点

新規チャットの送信は `NewChatLaunchRequest.worktreeStartPoint` を `spawnNewSession` → `SessionSpawnService.prepareSessionLaunchAsync` → `WorktreeIsolationGit.addWorktree` に渡す。既定は HEAD。作成直前に `WorkingTreeService` の `--no-optional-locks` 付き読み取りで commit ID に解決し、新規ブランチの起点にする。起点の削除・解決失敗では起動せず、既存の巻き戻しと失敗理由の表示へ戻す。復元・Control API・子セッションの既定の扱いは維持する。

一覧も `WorkingTreeService` が取得し、画面は `SelectablePopoverButton` で検索・選択する。本文は共有下書き、起点はプロジェクト別にメモリで保持する。詳細は [ADR 0203](../adr/0203-new-chat-worktree-start-point.md)。

起点候補はフォルダの変更時と、ポップオーバーを開くたびに読み直す。`SelectablePopoverButton` の提示内容の `.task` から取得し、閉じると未完了の取得はキャンセルする。同じフォルダの再取得中は前の候補を保持し、結果を取得してから置き換える。フォルダを変えたときだけ HEAD・空の検索へ戻す。

表示は作業場所の選択行の直下に右寄せする。元の操作列の幅を圧迫せず、長い起点名は途中を省略し、VoiceOver では全文を読む。

## 3. wait の完了検知（send↔wait 相関）

`ControllableSession` プロトコルは `submitBaselineTurnSeq: Int?` と `consumeSubmitBaseline()` を持つ（`Session/ControllableSession.swift`。`SessionViewModel`/`ChatSessionViewModel` が実装）。

- `sendText(_:submit:)` の submit==true 経路で `submitBaselineTurnSeq = completedTurnSeq` をスナップショット。
- `DashboardViewModel.waitUntilDone` は done を次のいずれかで返す:
  1. `completedTurnSeq > baselineTurnSeq`（wait 開始後に完了。既存）
  2. `submitBaselineTurnSeq` があり `completedTurnSeq > submitBaselineTurnSeq`（wait 開始前に完了したレース）
  3. sentinel 一致
- done を返す**全経路**で `consumeSubmitBaseline()`（`submitBaselineTurnSeq = nil`）を呼ぶ。`timedOut`/`notFound` では消費しない。
- `completedTurnSeq` は turn 完了で +1（PTY=Stop フック / チャット=`turnCompleted` イベント）。deadline は `ContinuousClock`（単調）。

これにより、fresh submit を伴わない単独の再 wait は消費済み（nil）で追加条件が不発火となり、旧来どおり次の turn を待つ（`timedOut`）。
