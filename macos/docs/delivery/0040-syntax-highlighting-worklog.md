---
status: active
last-verified: 2026-10-04
---

# 0040: シンタックスハイライトの判断と状態

## 判断

- [ADR 0180](../adr/0180-syntax-highlighting-with-in-house-lexer.md): 自前の ChatCodeTokenizer を広げる。tree-sitter・外部ハイライタは採らず、文脈依存の誤判定は受け入れる。
- [仕様 §2〜4](../specs/syntax-highlighting.md): ファイル名→拡張子→shebang→plain。Markdown ブロック編集も対象。色は既存トークンへ割り当て、新色を追加しない。未知フェンスの Swift フォールバックは現行互換を維持。
- 仕様 §5: 全文を背景で再計算し最新結果だけを反映。入力処理／属性適用 p95 16 ms、色付け完了 p95 150 ms は未測定の受け入れ基準。10,000 UTF-16 単位超の行を含む文書は本文色へ戻す。
- ADR 0030 の HighlightSwift 撤去はサイズの揺れに対する予防策。CPU 暴走の真因との区別を維持する。

## 状態

資料作成のみ。tokenizer・CodeTextEditor・ChatComposer・Package.swift を読み、既存の対応と未実装の要件を分けた。本体チェックアウトの設計書を絶対パスで参照し、指定 worktree の既存 2 資料へ新仕様のリンクを追加した。関連するスコープ外の記述に矛盾は無く、削除が必要な資料は見つからなかった。過去の見本合わせでプレーン表示を維持した記録（delivery 0039）は履歴として残し、今後は新仕様を優先する。

コード・パッケージ・凍結ファイルは未変更。コミット・push・merge はしていない。`compact-test 資料確認 python3 -c …` で資料 5 件の frontmatter・相対リンク・変更範囲・既存資料の差分を手元で確認し成功（リポジトリのテストには未登録。ラッパーは「要約未対応」）。`git diff --check` も成功。Swift テスト・ビルド・描画・性能測定・実 IME 入力は未実行。実装と検証は次段。
