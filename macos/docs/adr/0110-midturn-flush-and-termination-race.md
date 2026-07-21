---
status: active
last-verified: 2026-07-21
---

# ADR 0110: ターン途中 flush（leading-edge スロットル）と終了時の並行 flush + timeout race

## 文脈

作業中にアプリを閉じて開き直すと途中までの transcript が消えていた。原因は2点:
(1) flush がターン境界（turnCompleted/turnInterrupted/error）でしか走らない、
(2) アプリ終了経路が PTY kill のみ待ち、transcript 書き込みキュー（FIFO 直列 Task チェーン）の
完了を待たない。

## 決定

1. **ターン途中 flush**: 非 delta バリアイベントの到着で transcript を upsert する。
   leading-edge スロットル（初回は即 flush、以後 interval 1.0s / 32 件で間引き。clock/interval は
   注入可能）。書き込みは従来どおり TranscriptPersistenceQueue の FIFO 直列を維持。
2. **flushTranscriptNow()**: 保留 delta のバリア flush → 全量 upsert → キュー drain を await。
3. **終了経路（PhloxApp.applicationShouldTerminate）**: 全チャットセッションの
   `flushTranscriptNow()` を**並行に開始**し（直列だと先頭の store stall が後続を飢餓させる）、
   全体完了を **3s timeout と race** させて必ず reply を返す（`.terminateLater`）。
   race は `TerminationFlushRace`（withCheckedContinuation の先着1回 resume・detached Task）で実装。
   **withTaskGroup は使わない**——group はクロージャ終了時に残子を暗黙 await するため、
   timeout 勝利でも stall した flush 子を待ってしまう。非 throwing な `Task.value` の await は
   cancel で中断できないため、cancel 伝播でなく「待たない構造」で有界性を保証する。

## 結果

- 契約: `AcceptanceMidTurnPersistenceTests`（凍結）＋ `MidTurnPersistenceWhitebox` 系
  （スロットル・FIFO 順序・stalled store・starvation の白箱）。
- 既知の制限: SIGTERM/SIGKILL 経路とクラッシュは best-effort（通常終了のみ書き切りを保証）。
  timeout 勝利時の in-flight write はプロセス終了で打ち切られる（ハング回避を優先）。
