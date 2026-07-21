---
status: completed
last-verified: 2026-07-21
---

# 0010: スラッシュコマンドを文中どこでもハイライト＋サジェスト発火 worklog

agentic-loop（backend=external）による run 記録。実装は外部エージェント（Cursor ヘッドレス）へ委譲、PM（Claude）が問題定義・契約凍結・レビュー・統合・蒸留を担当。ユーザー要望「`/command` を入力の先頭以外でもハイライトし、サジェストもどの位置でも出す」を、発火境界＝空白・行頭の直後（`@` と同じ規則。単語境界方式は却下＝ユーザー承認）で実装。

## 何をしたか

| task | サーフェス | 内容 |
|---|---|---|
| task-1 | `ComposerHighlight.spans`（SessionFeature） | 先頭限定条件 `tokenStart == text.startIndex` を除去。`/` を `@` と同じ「トークン先頭ならどの位置でも」規則に統一。docstring 更新 |
| task-2 | `SuggestionTrigger.query`（SessionFeature） | 入力全体先頭の特別扱い `hasPrefix("/")` を撤去。`/`・`@` をカーソル直前トークン先頭の `switch token.first` に統一。`tokenRange`・`searchTerm` は `@` パス流用。docstring 更新 |

- 決定の理由（token-start vs 単語境界）は [ADR 0104](../adr/0104-composer-slash-trigger-position.md)。
- 構造の現況は [architecture/chat-mode-ux-components.md](../architecture/chat-mode-ux-components.md) の「@ サジェストの走査」節に追記。

## 検証

- 受け入れテスト2件を PM が新契約へ更新し凍結（実装前に red-for-the-right-reason 確認）。トークン途中 `/`（`src/main`）無視の回帰ガードを追加。
- `swift test`（`[Cc]omposer` フィルタ）: SessionFeature 36 / DashboardFeature 164 全 pass（persona-reviewer が独立実走）。
- 独立レビュー（persona-reviewer, stage1）: pass。MUST/HIGH/MEDIUM 0件。旧条件は全 Swift ファイルで grep 0件＝完全撤去を確認。
- 統合: macOS アプリ本体 `xcodebuild`（scheme Phlox, Debug）**BUILD SUCCEEDED**。描画側（`applyComposerHighlights` / `updateSuggestions`）は純関数結果を無条件消費で第3のゲート無しを Read 確認。
- 未実施: 実行中アプリでの対話 UI 確認（純関数＋無条件配線＋ビルドで挙動は確定と判断し、実機起動は省略）。

## スコープ外（不変）

- `@` の発火規則、句読点直後の発火（単語境界方式）、候補生成・非同期 coalescing（ADR 0053）・キールーティング、UI レイアウト、iOS 側。
