---
status: accepted
last-verified: 2026-07-26
---

# ADR 0029: サブエージェント画面の固まりは「件数窓」だけでなく「1メッセージあたりの描画バイト上限」で止める（先頭＋末尾を残す）

> **このファイルの役割**: サブエージェント詳細を開くと白画面で固まる問題に対し、なぜ件数の窓だけでは足りず、バイト数の予算を置いたかの決定理由。
> **書かないもの**: 本体 transcript の窓（→ `TranscriptWindow`）、サブエージェント表示の macOS 側構造（→ [macOS architecture/chat-subagent-display.md](../../../macos/docs/architecture/chat-subagent-display.md)）。

## 文脈

セッションで起動中のサブエージェントをタップすると**白画面のまま固まり操作できなくなる**（ユーザー報告）。`SubAgentDetailView` は `viewModel.visibleMessages` を `ForEach` で全件展開し、各メッセージの本文を丸ごと `DSChatBubble` / モノスペースカードへ渡していた。本体 transcript が持っている件数窓（`TranscriptWindow`・末尾 50 件）に相当する保護が無い。

原因究明の過程で、レビュアーが `ImageRenderer` によるヘッドレスレイアウト計測を行い、次を実測した。

| 入力 | レイアウト時間 |
|---|---|
| 1 MB | 0.130 秒 |
| 6 MB | 0.669 秒 |

**レイアウト費用は総バイト数にほぼ比例し、メッセージ件数にはほとんど依存しない**。つまり件数窓を入れても、`command` の出力や `fileChange` の diff が単一メッセージで数 MB になるケース（サブエージェントでは普通に起きる）には無効である。

## 決定

1. **件数窓を入れる**。`SubAgentDetailViewModel` に `TranscriptWindow` を持たせ、既定は本体 transcript と同じ末尾 50 件。`hiddenMessageCount > 0` のとき「以前のメッセージを読む（N件）」ボタンを出し、`expandVisibleWindow()` で窓を広げる。
2. **1メッセージあたり 16 KiB（`maxRenderedBytesPerMessage`）の描画バイト上限を置く**。`renderedBody(_:)` が UTF-8 バイト数で切り詰めた `RenderedBody { head, tail, omittedBytes }` を返し、View は全 case でこれを通してから SwiftUI へ渡す。
3. **切り詰めは先頭だけでなく「先頭＋末尾」を残す**（各およそ半分）。この画面の目的は「起動中のサブエージェントが**今**何をしているか」を見ることなので、先頭だけ残すと目的と逆向きになる。実行の文脈（先頭）と最新の出力（末尾）の両方を残す。
4. **省略は画面に明示し、コピーには全文を含める**。省略時は head と tail の間に「表示を省略しました（N バイト）。コピーには全文が含まれます。」を挟む。`ChatMessageCopyText.copyText(for:)` は切り詰め前の元メッセージから作るため、コピーは無損失のまま。
5. **切り詰めは `Character` 単位で進める**。マルチバイト文字や書記素クラスタの途中で切らない。
6. **初回ロード中は `DSConnectingIndicator` を出す**（`isInitialLoading`）。白画面のまま待たせない。

## 棄却案

- **件数窓だけ入れる**: 上の実測どおり、単一の巨大メッセージには効かない。ユーザーが報告した「固まる」ケースを再現できない可能性が高い。
- **先頭 16 KiB だけ残す**: 稼働中サブエージェントの最新出力が常に落ちる。画面の目的と逆。
- **文字数で切る**: 日本語と ASCII でレイアウト費用が数倍ずれる。実測した費用の相関はバイト数側にある。
- **`Text` を遅延化・仮想化する**: SwiftUI の `Text` は1つのビュー内部でレイアウトを分割できない。上限を置く以外に単一メッセージのレイアウト費用を下げる手段がない。

## 結果

- `AcceptanceSubAgentTranscriptWindowTests`（窓・ロード中表示）と `AcceptanceSubAgentRenderBudgetTests`（`RenderedBody` 契約・head+tail・境界・マルチバイト非破壊）で凍結した。
- **View 配線はソース assert でも凍結した**。値型だけをテストすると View を巻き戻しても green のままになるため（→ [macOS ADR 0124](../../../macos/docs/adr/0124-user-question-free-text-exclusive.md) の「結果」節に同じ判断の記録）。
- **実機での改善量は自動テストで裏が取れない**。固まっていた実セッションでの「タップから描画までの秒数」「戻るボタンの応答」は実機確認が要る。
