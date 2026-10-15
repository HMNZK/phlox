---
status: accepted
last-verified: 2026-10-15
---

# ADR 0203: 新規チャットの worktree の起点を選び、作成時に再解決する

## 文脈

ADR 0183 の新しい worktree は HEAD から作っていた。WS-1〜5 ではブランチ・タグ・コミットも起点にする。ADR 0188 により本文の下書きはアプリに 1 つであり、起点を覚える単位とは異なる。

## 決定

- 「新しい worktree」のときだけ既存の `SelectablePopoverButton` / `SelectablePopover` による検索可能な起点欄を置く。既定は「今の位置（HEAD）」。起点はプロジェクト別にメモリで保持し、本文の共有を変えない。
- 一覧とコミット ID の検証は `WorkingTreeService` の読み取り経路（`--no-optional-locks`）を拡張する。ローカルは更新日時の降順、リモートは HEAD の別名を除外し、タグと HEAD から 30 件の履歴も表示する。取得失敗時は HEAD だけを表示する。fetch はしない。
- ブランチ・タグは完全な ref 名で保持し、名前の衝突を防ぐ。16 進 4 文字以上の直接入力は commit として実在を検証し、解決した ID を選択値にする。
- 起動要求に選択値を固定する。既存の `WorktreeIsolationGit` が作成直前に commit ID を再解決し、`git worktree add -b <branch> <path> <commit>` へ渡す。復元済みブランチはこれまでどおり使う。
- 起点が消えていたら作成とセッション起動を中止し理由を表示する。ADR 0170 の中止方針と既存の巻き戻しを維持する。

## 理由と結果

既存の読み取りと作成の経路を拡張すれば別の git 実行器は不要になる。HEAD の既定動作を保ち、選択後に ref が移動した場合は開始時点の位置を使う。ADR 0170・0183 の失敗時の扱いは置き換えず、起点の選択だけを追加する。

仕様: [WS-1〜5](../specs/git-tab-workflow-and-worktree-start.md#4-ワークツリーの起点ws)。
