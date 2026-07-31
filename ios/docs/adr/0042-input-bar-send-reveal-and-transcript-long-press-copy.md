---
status: active
last-verified: 2026-07-31
---

# ADR 0042: 実行中の送信ボタンを入力開始で現し、転写のコピーを長押しへ集約する

## 文脈

実機で 2 つの不具合が挙がった。

1. **作業中に追加指示を送れない**。入力バー右端は 1 スロットで、`isRunning` なら停止ボタンが送信ボタンを**置き換える**設計だった（[ADR 0018](0018-input-bar-remove-drag-and-voice.md)）。エージェント実行中はこのスロットが停止ボタンで占有され、送信手段が画面から消えていた。`SessionDetailViewModel.sendMessage()` は実行中でも送れる（API 側の制約はない）ので、これは UI だけの制約だった。macOS 版（`ChatComposer`）は停止と送信を**併置**しており、モバイルだけが送れない状態でもあった。
2. **転写の各行にコピーボタンが常設されていて鬱陶しい**。`SessionDetailView` / `SubAgentDetailView` は行を `HStack` で包み、右余白に `ChatMessageCopyButton` を毎行置いていた。バブルは wave-4 で既に常時表示のコピーボタンを撤去して長押し `contextMenu` へ移行済み（`providesAlwaysVisibleCopyButton = false`）で、転写側だけが逆行していた。

## 決定

- **送信/停止の 1 スロット排他表示を廃し、状態を 3 値へ広げる。** `DSInputBarActionState` を `enum`（`.send(isEnabled:)` / `.stop`）から `struct { showsStop, showsSend, sendIsEnabled }` へ変更する。

  ```swift
  showsStop    = isRunning
  showsSend    = !isRunning || hasText || isLoading
  sendIsEnabled = canSubmit(text:isLoading:)   // 従来どおり
  ```

  - 非実行中は従来どおり送信ボタンを**常設**する（空文字・送信不能時は `.disabled` ＋ `opacity(0.45)` の無効・淡色）。ここは ADR 0018 の決定を維持する。
  - 実行中は、**何も打っていない間は停止ボタンだけ**を置き、打ち始めたら送信ボタンを併置する。`isLoading`（送信直後は楽観クリアで本文が空になる）でも送信スロットを保ち、進捗表示が途中で消えないようにする。
  - 出現は `.transition(.move(edge: .trailing) + .opacity)` ＋ `.animation(DSMotion.spring, value: actionState)` で、右から現れ停止ボタンが左へ寄る。
- **転写のコピーを長押し `contextMenu` へ集約する。** 行ごとの `ChatMessageCopyButton` を撤去し、バブルと同じ `chatMessageCopyContextMenu` を全行へ適用する。コマンド群・差分のように連結が高コストなものは、遅延生成を保つため `ChatMessageDeferredCopyText`（`() -> String?` を保持する値型）を受ける overload を足す（[ADR 0038](0038-command-group-cost-bounding.md) 決定3の遅延をそのまま引き継ぐ）。孤児化した `ChatMessageCopyButton` は削除する。

## 結果

- [ADR 0018](0018-input-bar-remove-drag-and-voice.md) の「送信/停止を右スロットに**排他**で常設する」部分はこの ADR が置き換える（`superseded-by: 0042`）。ドラッグバー・音声入力の撤去は有効なまま。
- wave-6 の `.none`（空文字時は送信ボタンを出さない）を wave-7 で廃止した経緯があるが、今回それは**実行中だけの条件**として `showsSend` に戻った。非実行中の常設は廃止していないので、wave-6 への差し戻しではない。
- 契約テスト（`DSInputBarWave6Tests` / `Wave7InputBarContractTests`）は 3 値へ更新し、実行中・空入力／実行中・入力あり／送信中を固定した。実挙動は `PhloxMobileUITests/SessionInputBarRunningUITests` が実描画で裏取りする（空入力では送信ボタンが存在せず、入力すると出現し停止も残ること）。
- `DSChatBubble.providesAlwaysVisibleCopyButton = false` が転写全体で成り立つようになり、コピーの作法が 1 つに揃った。
