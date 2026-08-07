---
status: accepted
last-verified: 2026-08-07
---

# エディタパネルの Git 状態詳細は展開可能なスクロール領域で表示する

## Context

Git の失敗出力は複数行になる。固定高でクリップすると原因を読めず、誤った再試行につながる。

## Decision

通常時は状態の要約を表示し、失敗時は `DisclosureGroup` の「詳細」から全文を開けるようにする。詳細本文は固有高を持つ `ScrollView` に置き、選択・コピー可能にする。変更一覧を含む split 列は外側の単一 `ScrollView` にして、ネストしたスクロール領域を避ける。

## Consequences

通常のコミット操作はコンパクトに保たれ、必要なときだけ失敗理由の全文を読める。旧 ADR 0169 の `stackedCommitPanelBudget` と `commitStatusMaxHeight` を前提にした固定高方針は superseded とする。

## Addendum (2026-08-07)

split と stacked のどちらでも、Git 状態詳細の内側 `ScrollView` は、そのパネルを収める外側 `ScrollView` と入れ子になることを許容する。内側に Dynamic Type 対応の固有高を与えるため、入れ子でも高さ 0 に潰れず、外側でパネル全体、内側で長い失敗出力をそれぞれ到達可能にする。

`EditorPanelLayout.splitMinimumWidth` は SwiftUI 環境に依存しない純粋な幅判定として据え置く。Dynamic Type に合わせて閾値を増やすと、環境値を判定関数へ持ち込み白箱テスト可能な規則を失うためである。アクセシビリティ文字サイズで列が窮屈な場合は stacked へ切り替わらないトレードオフを受け入れ、利用者がドロワー幅を広げられる現在の挙動を維持する。
