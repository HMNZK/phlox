---
status: accepted
last-verified: 2026-07-26
---

# ADR 0028: セッションが completed / error でも入力欄を有効のままにする（無効にするのは starting だけ）

> **このファイルの役割**: 停止したセッションで入力欄を出し続ける決定と、その根拠。
> **書かないもの**: 入力欄の見た目・構成（→ [ADR 0016](0016-input-bar-compact-pill-redesign.md)・[ADR 0018](0018-input-bar-remove-drag-and-voice.md)）。

## 文脈

モバイルで追加したセッションがエラーで停止すると、**入力欄が画面から消えて何も入力できなくなる**（ユーザー報告）。`SessionDetailViewModel.inputEnabled` が `starting` / `completed` / `error` の3状態を無効としていたためである。

セッションが停止していても、ユーザーから見れば「もう一度話しかければ再開してほしい」対象である。実際 Claude Code バックエンドには respawn 機構があり、送信すれば CLI プロセスが起こし直される（→ macOS [architecture/claude-chat-session-lifecycle.md](../../../macos/docs/architecture/claude-chat-session-lifecycle.md)）。**入力できないことによって、復帰できるはずのセッションが操作不能な墓場になっていた**。

## 決定

1. **`inputEnabled` を無効にするのは `starting` だけにする**。`completed` / `error` も含めて、それ以外はすべて有効。
2. **初回 spawn 待ち（`isAwaitingInitialSpawn`）は従来どおり有効**（変更なし）。

## 棄却案

- **`error` のときだけ「再開する」ボタンを別途出す**: 入力欄が消える問題は残り、UI 要素が増える。ユーザーの期待は「入力して送れば動く」ことであり、専用ボタンは余計な段差になる。
- **停止中は入力を受け付けるが送信をブロックし、エラーを出す**: 送れないなら入力欄がある意味がない。

## 結果

- `ErrorInputBarWhiteboxTests` / `AcceptanceErrorInputBarTests` で、各 `SessionStatus` に対する `inputEnabled` の値を全数検証した（`starting` のみ false）。
- **respawn 機構を持たないバックエンドでは、送信しても復帰しない可能性がある**。本 run の調査時点で Codex には respawn 機構が無い。その場合ユーザーは送信してエラーが返ることになるが、「入力欄が消えて何もできない」よりは改善である。Codex の respawn は本 run のスコープ外の申し送りとする。
