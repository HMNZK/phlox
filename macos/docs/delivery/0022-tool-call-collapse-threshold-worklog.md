---
status: completed
last-verified: 2026-07-27
---

# 0022: ツールコール件数と折りたたみ閾値の分離（macOS）作業ログ

> **このファイルの役割**: `feature/tool-call-collapse-threshold` の macOS 側で何をしたか、どこまで検証したかの記録。
> **書かないもの**: 決定の理由（→ [ADR 0131](../adr/0127-transcript-window-counts-blocks.md) / [ADR 0132](../adr/0128-command-group-cost-bounding.md)）。現状の構造（→ [architecture/chat-mode-ux-components.md](../architecture/chat-mode-ux-components.md)）。

## 背景

ユーザー報告:「ツールコールが多いだけでメッセージが折りたたまれてしまう。ツールコールの数と折りたたむ閾値は無関係にしてほしい。」

調査の結果、件数に依存する機構が2つあった。詳細は ADR 0131 のコンテキスト節。

## やったこと

### task-1: グルーピング統一と表示窓のブロック単位化

- `ChatTranscriptGrouping.blocks(from:)` の「1件なら `.single`」分岐を削除（1件以上で常に `commandGroup`）。
- `visibleSlice(from:startingAt:)` を `visibleSlice(from:blockLimit:)` へ置換。`ChatTranscriptSlice.hiddenItemCount` → `hiddenBlockCount`。
- 窓境界が必ずブロック境界になるため、旧「部分ブロック」処理（境界がグループ内部のとき先頭ブロックの id を差し替える）を削除。
- `blockCount(of:)` / `blockIndex(ofItemWithID:in:)` を新設し、`ChatTranscriptView.jumpToTarget` が item index → block index を翻訳してから `TranscriptWindow.reveal` に渡すようにした。
- `TranscriptWindow.swift` は**無変更**（API・定数・`reveal` 実装すべて）。

### task-2: ツール実行カードのコスト有界化

- `CommandGroupPresentation` を `CommandGroupHeader`（行データを持たない）と `CommandGroupRowWindow.slice(...)`（展開時のみ）へ分離。
- `CommandGroupCell` に `@State rowLimit` と「残り N 件を表示」ボタンを追加（`accessibilityIdentifier("CommandGroupCell.loadEarlierRows")`）。
- 空出力フィルタを唯一の行に適用しない規則を iOS から移植（task-1 が入れた「単独・空出力のコマンドがカードごと消える」回帰の解消）。

## 検証

| 検証 | 結果 |
|---|---|
| `swift test --package-path macos/Packages/SessionFeature` | 443 tests / 62 suites passed |
| `swift test --package-path ios/Packages/PhloxKit` | 599 tests / 117 suites passed |
| `swift build --package-path macos/Packages/AppBootstrap` | 成功 |
| 消費側パッケージのビルド（DashboardFeature / TerminalUI / MobileProxy） | すべて成功 |
| 独立レビュー（Claude `persona-reviewer`・Codex 実装とは別モデル） | task-1 pass / task-2 pass |

**未検証**: Xcode でのアプリ本体ビルド（`xcodegen` がこの環境に無く `Phlox.xcodeproj` を生成できない）。実機・実セッションでの見た目とスクロール挙動。

## 積み残し

- レビュー指摘 LOW: `TranscriptRenderCostWhiteboxTests` の「1000件すべてコマンド」ケースは1ブロックに畳まれるため上限アサーションが自明に真になる。binding なケースを別途1件追加して補った。
- レビュー指摘 LOW: 実行中グループでは新着 item が末尾へ積まれるため、「残り N 件を表示」で開いた古い行が再び窓の外へ出る。transcript 本体の窓と同じ性質として受容（ADR 0132 の既知の限界）。

## 生成・更新したドキュメント

- 新規: [ADR 0131](../adr/0127-transcript-window-counts-blocks.md) / [ADR 0132](../adr/0128-command-group-cost-bounding.md)
- 更新: [ADR 0096](../adr/0096-chat-tool-call-grouping.md)（`superseded` へ・後日談を追記）、[adr/README.md](../adr/README.md)、[architecture/chat-mode-ux-components.md](../architecture/chat-mode-ux-components.md)
