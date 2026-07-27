---
status: active
last-verified: 2026-07-27
---

# ADR 0038: iOS のツール実行カードは閉状態で行データもコピー文字列も作らず、展開時は行数を有界化する

## ステータス

採択・実装済み（2026-07-27, `feature/tool-call-collapse-threshold`）。[ADR 0037](0037-transcript-window-counts-blocks.md) と対で読む。macOS の [ADR 0128](../../../macos/docs/adr/0128-command-group-cost-bounding.md) と同じ決定に、iOS 固有のコピー経路の対処を加えたもの。

## コンテキスト

ADR 0037 で表示窓がブロック単位になった結果、**1つの `commandGroup` が数百〜数千件のツール実行を抱えうる**ようになった。この前提変化で3つの問題が露出した。

1. **閉じていても全件を走査していた。** `SessionDetailCommandGroupPresentation.init` は折りたたみ状態でも全 message から `rows` を作っていた。transcript は非 Lazy（ADR 0022）でストリーミングのたびに body が再評価される。
2. **展開すると全件を一度に描画していた。**
3. **コピー用テキストを毎 body 生成していた。** `SessionDetailView` の commandGroup 分岐が `commandGroupCopyText(items)` を eager 評価し、**カードが閉じていても**全件の `copyText(for:)` を呼んで1本の String に連結していた。件数比例の文字列連結であり、行データ構築より重い。

## 決定

1. **ヘッダと行データを型で分ける。**
   - `SessionDetailCommandGroupHeader`（`title` / `isRunning` / `shouldRender`）— 行データを保持しない。
   - `SessionDetailCommandGroupRowWindow.slice(items:lastTranscriptID:isTurnRunning:limit:)` — 展開時にだけ呼ぶ純関数。
   - 行構築の呼び出しは `if isExpanded { ... }` の内側に置く。
2. **展開時にも行数の窓を置く。** `defaultLimit = 50` / `expandStep = 50`。表示対象行の末尾 50 件を出し、残りは「残り N 件を表示」ボタンで段階展開する。
3. **コピー用テキストは押下時にだけ生成する。** `ChatMessageCopyButton` に `textProvider: () -> String?` を受ける init を足し、生成を遅延させる。ボタンの表示可否は短絡評価で判定する。
4. **コピー可否の判定と文字列生成を1本の純関数から導く。** `ChatMessageCopyText.commandGroupCopyablePart(for:)` を単一の正本とし、`commandGroupHasCopyableText`（`contains(where:)` で短絡）と `commandGroupCopyText`（`compactMap` + `joined`）の両方がこれを通る。

## 結果

- 閉じたカードの body 評価コストがグループ件数に依存しなくなる（`shouldRender` の短絡走査だけが残る）。
- 展開しても一度にレイアウトされる行は 50 行までに有界化される。
- **決定4は correctness の問題でもあった。** 当初の実装は可否判定を `Character.isWhitespace`、文字列生成を `CharacterSet.whitespacesAndNewlines` という**別々の「非空白」定義**で書いており、両者は同じ集合ではない。ゼロ幅スペース `U+200B` だけの出力では「コピーボタンは出るのに押しても何も起きない」状態になっていた（独立レビューが実測で検出）。1本の関数から導くことで、この種の食い違いが構造的に起こらなくなる。空判定は変更前と同じ `!text.isEmpty`（空白のみの文字列は落とさない）。
- 旧 `SessionDetailCommandGroupPresentation` は削除した。

## 既知の限界（意図的に受け入れたもの）

- `shouldRender` は全件が空出力という最悪ケースでのみ N 件を走査する（生成は伴わない）。macOS の [ADR 0128](../../../macos/docs/adr/0128-command-group-cost-bounding.md) と同じ扱い。
- **「閉状態で行データもコピー文字列も作らない」は SwiftUI の body 評価を単体テストから観測できないため、ソース検査の白箱テストで固定した**（`slice` の呼び出しが `if isExpanded` ブロック内にあること、commandGroup 分岐が `copyTextProvider:` を渡していることを実ソースから検証する）。eager に書き戻すと落ちることを変異試験で確認済み。整形の変更で偽陽性になりうる脆さは受け入れた。

## 凍結テスト

- `ios/Packages/PhloxKit/Tests/FeaturesTests/AcceptanceIOSCommandGroupRowWindowTests.swift` — 5000件でもヘッダが正しい・展開直後の行数 ≤ 50・`hiddenRowCount`・単独空出力の描画・複数件全空出力の非描画
- `ios/Packages/PhloxKit/Tests/FeaturesTests/AcceptanceIOSToolCallGroupingTests.swift` — 既存3件を新 API へ移行（アサーションの意味は不変）
