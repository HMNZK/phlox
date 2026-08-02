---
status: completed
last-verified: 2026-08-02
---

# 0032: thinking-indicator-freeze run 作業ログ

Thinking インジケータ（点描 orb ＋ シマーする状態語 ＋ 経過秒）がセッション実行中に止まったまま戻らない不具合を直した agentic-loop run（multi モード・backend=codex(gpt-5.6-terra)）の記録。

## 経緯

ユーザー報告は「実行中にシマーと経過秒が止まる」。スクリーンショットは状態語が静止し経過秒が `0s` で固定、直上に完了直後のサブエージェントカードがある像だった。追加の体感として「作業時間が長いターン」「サブエージェントを開いたとき」が挙がった。

調査で、シマーと経過秒は同一の `isTimelineVisible` で駆動されており（片方だけ止まることはない）、その入力のうち `isInTranscriptViewport`（`ChatAutoFollow.isAtBottom` の流用）が**スクロール系イベントでしか更新されない**ことを特定した。決定・機序・トレードオフ・残余は **[ADR 0159](../adr/0159-thinking-indicator-viewport-signal-recovery.md)**、影響を受けた既存決定への注記は **[ADR 0067](../adr/0067-thinking-wave-animation-and-viewport-pause.md)** に置いた。現行構造の記述は `architecture/chat-mode-ux-components.md` を更新した。

## タスク

| task | 内容 | difficulty | 結果 |
|---|---|---|---|
| task-1 | 非アクティブウィンドウでも止めない（`scenePhase != .background`） | standard | done。独立レビュー 2 ラウンドで pass |
| task-2 | 可視性シグナルの固着解消（コンテンツ寸法変化・documentView 差し替えでも再評価） | deep | done。独立レビュー 3 ラウンドで pass |

実装は Codex（gpt-5.6-terra）、独立レビューは Claude `persona-reviewer`（実装者と別モデルの規則）。

## 状態スナップショット（run 終了時）

- テスト: SessionFeature **821** / DesignSystem **111** green（ベースライン 808 / 111 から +13）。
- 実機: Debug 版をリリース版と併存起動して SC-5 (a)〜(d) と CPU 収束を実測（結果は ADR 0159 の「検証」表）。**リリース版は終了させていない**。
- 未検証として残したもの: 長時間ターンの観測が最長 2 分 30 秒（3 分以上は未確認）、グリッド表示での CPU。

## この run で学んだこと（機構側）

- **同一テストターゲットを共有する複数タスクの受け入れテストを、フェーズ1 で同時に凍結すると、先に走るタスクの「全数 green」が原理的に達成不能になる**。task-1 が `status: partial` で止まり、PM が契約の欠陥と裁定して「凍結の単位はタスク、投入の単位はビルド単位」へ改めた（task-2 の受け入れテストを `tasks/staged/` へ退避し、ディスパッチ直前に配置してコミット）。
- **独立レビューが「テストが本当に何かを守っているか」を変異検証で暴いた**。task-2 の白箱テストは初版では差し替え先の観測を担保しておらず、固着バグを再導入する変異を入れても green のまますり抜けた。レビュアーが standalone ビルドで変異を実行して発見し、テスト側 3 行の是正で解消した。テストの存在ではなく**変異で赤くなること**を合格条件にする価値が実証された。
- **Rubric に「静的には証明できないこと」を要求すると差し戻しが増える**。task-2 の「帰還ループの2状態収束をコードで説明できるか」は ADR 0030 自身が「静的解析では検出不能」と記録していた性質で、PM が証明の本体をフェーズ4 の実機 CPU 実測へ移して決着させた。
