---
status: active
last-verified: 2026-07-08
---

# 0052: チャットセル派生値の内容キー・メモ化（非観測 NSCache）と FileChange 表示ポリシーの純導出

> **このファイルの役割**: body 評価毎の重い再計算（Markdown 分割・シンタックスハイライト・diff 分類）をどうキャッシュするかの決定と、キー設計・保管場所の rationale。
> **書かないもの**: 現行の実装仕様（→ `architecture/chat-mode-ux-components.md`）。

- **文脈**: 監査所見 P2/P4/N3。ChatMessageCells は body 評価毎に `splitFencedCodeBlocks`／`highlight`（非トークン文字を1文字ずつ AttributedString 連結）／`DiffLineClassifier.classify`（diff 全行）を再実行しており、ストリーミング中の全セル再評価で CPU を浪費していた。
- **決定**:
  1. **キー＝入力文字列の内容そのもの**（`ContentMemoCache`、NSCache<NSString, Box>）。item.id や本文長をキーに使わない——ストリーミングで同一 id の本文が伸長し続けるため id/長さキーは同長別内容で stale ヒットする（正しさハザード）。countLimit=512 で LRU 退避（中間文字列の無制限蓄積を防ぐ）。
  2. **保管は非観測の static ストレージ**。@Observable/@State を一切経由しないため、body 評価中の書込が view 無効化を誘発しない（ADR 0010 の「描画中の観測 state 変更→無限再無効化」に構造的に該当しない）。
  3. **highlight は同色 run をまとめて append**（1文字連結の廃止）。旧実装との AttributedString 完全一致（==）を白箱で敵対的入力込みで固定。
  4. **FileChange の既定展開は純導出** `isExpanded(userOverride:lineCount:)`。`@State(initialValue:)` への焼き込みは同一 item.id の置換（Cursor の started→completed）で再適用されない SwiftUI の identity 特性があるため棄却（stage2 レビューが実経路付きで指摘）。閾値200行超は既定折りたたみ・表示は500行上限＋「さらに表示」。
- **棄却案**: (a) id＋本文長キー（stale ヒット）、(b) @Observable プロパティへのキャッシュ（ADR 0010 再発）、(c) 展開状態の onChange 書き戻し（イベント順序に敏感・純導出の方が安全）。
- **証拠**: 受け入れ（同値凍結4＋ポリシー1）＋白箱8 green、既存 highlight/render 凍結テスト green 維持。実機ストリーミングで CPU バースト後即収束（2026-07-08）。
