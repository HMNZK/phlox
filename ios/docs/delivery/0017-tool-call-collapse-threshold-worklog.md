---
status: completed
last-verified: 2026-07-27
---

# 0017: ツールコール件数と折りたたみ閾値の分離（iOS）作業ログ

> **このファイルの役割**: `feature/tool-call-collapse-threshold` の iOS 側で何をしたか、どこまで検証したかの記録。
> **書かないもの**: 決定の理由（→ [ADR 0037](../adr/0037-transcript-window-counts-blocks.md) / [ADR 0038](../adr/0038-command-group-cost-bounding.md)）。現状の構造（→ [architecture/overview.md](../architecture/overview.md)）。

## 背景

ユーザー報告:「ツールコールが多いだけでメッセージが折りたたまれてしまう。ツールコールの数と折りたたむ閾値は無関係にしてほしい。」

iOS は [ADR 0026](../adr/0026-ios-single-toolcall-grouped-row.md) で既に「1件でも集約」に統一済みだったため、**集約条件の変更は不要**。窓の数える単位だけが問題だった。詳細は ADR 0037 のコンテキスト節。

## やったこと

### task-3: 表示窓のブロック単位化

- `SessionDetailToolCallGrouping.visibleSlice(from:startingAt:)` を `visibleSlice(from:blockLimit:)` へ置換。`SessionDetailTranscriptBlockSlice.hiddenItemCount` → `hiddenBlockCount`。`blockCount(of:)` を新設。
- 窓境界が必ずブロック境界になるため、旧「部分ブロック」処理を削除。
- `SessionDetailTranscriptSlice` の `visibleMessages` を可視ブロック列から導くようにした。
  - **独立レビューの指摘で作り直した**: 初回実装は先頭可視ブロックの id を全 message 列から逆引きして範囲を決めており、(a) 契約が要求していない「`ChatMessage.id` が一意」という前提を持ち込み、(b) body 評価パスに O(n) 走査を1本足し、(c) 不変条件が破れたときに空スライスで黙って埋める分岐を持っていた。可視ブロックの件数から `messages.suffix(n)` を取る形へ変更し、3つとも解消した。
- `TranscriptWindow.swift` と `SubAgentDetailViewModel.swift` は**無変更**。

### task-4: ツール実行カードのコスト有界化

- `SessionDetailCommandGroupPresentation` を `SessionDetailCommandGroupHeader`（行データを持たない）と `SessionDetailCommandGroupRowWindow.slice(...)`（展開時のみ）へ分離。
- `@State rowLimit` と「残り N 件を表示」ボタンを追加（`accessibilityIdentifier("SessionDetailToolCallGroupRow.loadEarlierRows")`）。
- コピー用テキストの生成をボタン押下時まで遅延（`ChatMessageCopyButton(textProvider:)`）。
  - **独立レビューの指摘で作り直した**: 初回実装は可否判定を `Character.isWhitespace`、文字列生成を `CharacterSet.whitespacesAndNewlines` という別々の定義で書いており、ゼロ幅スペース `U+200B` だけの出力で「ボタンは出るのに押しても何も起きない」状態になっていた。`commandGroupCopyablePart(for:)` 1本から両方を導く形へ変更した。
- 「閉状態で行データもコピー文字列も作らない」をソース検査の白箱テストで固定（eager に書き戻すと落ちることを変異試験で確認済み）。

## 検証

| 検証 | 結果 |
|---|---|
| `swift test --package-path ios/Packages/PhloxKit` | 599 tests / 117 suites passed |
| `swift test --package-path macos/Packages/SessionFeature` | 443 tests / 62 suites passed |
| `swift build --package-path macos/Packages/AppBootstrap` | 成功 |
| `swift build --package-path ios/Packages/PhloxKit` | 成功 |
| 独立レビュー（Claude `persona-reviewer`・Codex 実装とは別モデル） | task-3 pass（差し戻し1回）/ task-4 pass（差し戻し2回） |

**未検証**: Xcode でのアプリ本体ビルドとシミュレータ実行（`xcodegen` がこの環境に無く `PhloxMobile.xcodeproj` を生成できない）。実機での見た目・コピー操作・「残り N 件を表示」の操作感。

## 積み残し

- レビュー指摘 LOW: ソース検査テストは完全一致文字列に依存しており、整形の変更だけで偽陽性になりうる。
- レビュー指摘 LOW（受容）: `shouldRender` は全件が空出力の最悪ケースでのみ N 件を走査する（生成は伴わない）。ADR 0038 の既知の限界。

## 生成・更新したドキュメント

- 新規: [ADR 0037](../adr/0037-transcript-window-counts-blocks.md) / [ADR 0038](../adr/0038-command-group-cost-bounding.md)
- 更新: [ADR 0026](../adr/0026-ios-single-toolcall-grouped-row.md)（後日談を追記・macOS との差異が解消した旨）、[adr/README.md](../adr/README.md)、[architecture/overview.md](../architecture/overview.md)
