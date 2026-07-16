---
status: active
last-verified: 2026-07-04
---

# ADR 0009: 子プロセスのライフサイクル堅牢化（孤児化防止）

- ステータス: Accepted（実装・検証済み、feature/process-lifecycle-fix）
- 作成日: 2026-06-15
- コンテキスト: spawn した claude/codex セッション（およびその OS 子孫）が、特定の終了経路で kill されず
  孤児化して残り続ける問題があった。実機で CPU 100% を 17 時間焼く孤児 codex と、18 時間アイドルの孤児
  claude 群（いずれも PPID=1）を観測。原因となる 3 つのライフサイクル欠陥（D1/D2/D3）の修正方針を記録する。

## 1. 背景

各セッションは `POSIX_SPAWN_SETSID`（`Posix.swift`）で pgid==pid の独立プロセスグループとして起動される。
これを前提に、次の非対称・欠落があった。

- **D1: 個別 kill が単一 PID**。`PTYManager.kill(_:)` は `Posix.terminate`（`kill(pid, SIGTERM)`）で
  セッション自身にしか SIGTERM を送らず、そのセッションが spawn した OS 子孫（孫）が孤児化した。一括終了
  `terminateAllAndWait` は `killpg` を使うのに個別 kill だけグループ化されていなかった。
- **D2: 異常終了で後始末しない**。子の一括終了は `applicationShouldTerminate`（GUI 正常終了）でしか走らず、
  SIGTERM/SIGINT/クラッシュではシグナルハンドラ・`atexit` が無く全孤児化した。
- **D3: レジストリが実プロセスと非同期**。`PersistedSessionDescriptor` に `pid` が無く、起動時 `restore` は
  再 spawn のみで前回プロセスの死活確認・掃除（reconcile/reap）をしなかった。クラッシュのたびに孤児が蓄積し、
  `sessions.json` と実プロセスが drift した。

## 2. 決定事項

### 2.1 個別 kill をプロセスグループ kill に統一（D1）
- `PTYManager.kill(_:)` を `Posix.terminateGroup`（`killpg`）に変更し、対象セッションの pgid 配下（孫まで）を
  終了させる。各セッションは SETSID で自前 pgid のため他セッションには波及しない。`Posix.terminate`（単一 PID 版）は
  互換のため残置。

### 2.2 SIGTERM/SIGINT 受信時のグレースフル終了（D2）
- AppDelegate に SIGTERM/SIGINT 用 `DispatchSource` を設置（既定動作を `SIG_IGN` で無効化してから resume）。
  ハンドラは `terminateAllAndWait` の完了を `DispatchSemaphore` で待ってから `exit(0)`。
- ハンドラは MainActor を経由しない。`PTYManager`（独立 actor・Sendable）参照を nonisolated でスレッド安全な
  箱 `SignalSafeBox`（`NSLock` 保護）に保持し、`ptyManager` 代入の `didSet` で同期更新する。これにより
  **MainActor がブロック中でも** cleanup が完走する。
- idempotency は `CleanupGuard`（`NSLock` 直列化フラグ）で担保し、`applicationShouldTerminate` 経路と二重実行しない。
- SIGKILL（kill -9）・ハードクラッシュはプロセス内で捕捉不可。その取りこぼしは §2.3 の起動時 reap が回収する。

### 2.3 pid 永続化 + 起動時 reconcile/reap（D3）
- `PersistedSessionDescriptor` に `pid: pid_t?` を追加（Optional・`encodeIfPresent`/`decodeIfPresent` で旧 JSON 後方互換）。
- 新規 spawn 時と復元・再 spawn 後の両方で、実 pid を `livePIDProvider` 経由で descriptor に書き戻す
  （`PTYManager.pid(for:)` を public 化し `CompositionRoot` で `{ id in await pty.pid(for: id) }` を配線）。
  ※復元後にも書き戻すことで、反復クラッシュでも次回起動の reconcile が新世代の孤児を掃除できる。
- 起動時 `restoreSession` 冒頭で、記録 pid が生存していれば `OrphanReaper`（既定 `Posix.killGroup`）で reap してから
  cold-restart 再 spawn する（master fd を失った孤児は再アタッチ不能なため reap→再 spawn）。死亡・nil は従来どおり。

## 3. 採用しなかった/見送った案
- **孤児プロセスの再アタッチ（adopt）**: デーモン死で master fd が失われ PTY 再接続は不能。reap→再 spawn を採る。
- **二重起動（複数 Phlox 同時稼働）対応**: 既存設計でも未サポート（ポート競合）。本 ADR の reap は単一インスタンス前提で、
  registry に記録された自分の pid 以外には一切シグナルを送らない。pid 再利用の理論的リスクは既知制約として残す。

## 4. 影響
- 個別 kill・シグナル終了・クラッシュ後の再起動のいずれの経路でも、子孫プロセスが孤児として残らない。
- `sessions.json` に `pid` フィールドが増えるが Optional で後方互換（旧データは pid=nil で従来挙動）。
- `OrphanReaper` は注入可能で、reconcile ロジックは実プロセスを使わずユニットテスト可能。
- 検証: PTYKit/AgentDomain/DashboardFeature/AppBootstrap の `swift test`、ヘッドレス E2E、App の `xcodebuild` がいずれも green。

## 5. 関連
- ADR 0004 §2.1（kill 時の子セッション reparent／parentSessionID 永続化）は ADR 0013（2026-06-17）で廃止され、論理セッションの削除もカスケード化された（親削除で子孫セッションを再帰削除）。本 ADR が扱う「kill 対象セッション自身の OS 子孫プロセスの終了」は、論理セッションの削除方式とは別レイヤとして引き続き有効。
