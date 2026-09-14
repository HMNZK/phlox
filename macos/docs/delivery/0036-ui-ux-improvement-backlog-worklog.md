---
status: completed
last-verified: 2026-09-14
---

# 0036: UI・UX 改善バックログ完了 worklog

> **このファイルの役割**: UI-01〜08、UX-01〜12、BUG-01〜02 を完了した run の状態と、合否外で残した追跡項目を残す。
> **書かないもの**: 現行仕様（→ [spec](../specs/ui-ux-improvement-backlog.md)）、決定理由（→ [ADR 0175](../adr/0175-transcript-answer-and-process-separation.md)）。

## 完了した範囲

22 件を実装・検証した。恒久的な決定の変更は、回答と処理詳細の区別を定める [ADR 0175](../adr/0175-transcript-answer-and-process-separation.md)、復元中削除の繰り越しを注記した [ADR 0024](../adr/0024-restore-gate-and-commands-reactivity.md)、表示名の末尾省略を注記した [ADR 0073](../adr/0073-overlay-inset-by-measured-height.md) に反映した。BUG-01 の端末表示切替修正は [ADR 0174](../adr/0174-terminal-mount-ownership-prevents-blank-after-view-mode-switch.md) を参照する。

受け入れテスト、配線検査、独立レビュー、PM の実画面記録は各タスクの run 記録にある。本 worklog の作成時にはそれらを再実行していない。

## フォローアップ

| 項目 | 記録済みの事実 | 出典 |
|---|---|---|
| 履歴スクラバー | 倍率 2.0 でチップ `workspace` がエラーカードの時刻と重なり、時刻の左が欠けた。既存挙動かは未確認。 | [visual-task-40-a](../../../docs/agent-output/visual-task-40-a.md) |
| テーマ切替 | `PhloxApp` の `preferredColorScheme` は `ThemeStore.active` を購読しないため、実行中テーマ切替でウィンドウ外観だけ遅れる余地がある。未再現。 | [decision log](../../../decision-log.md)、[visual-task-40-b](../../../docs/agent-output/visual-task-40-b.md) |
| task-44 の履歴名 | meta のみの履歴を再開したとき、名前を復元する制限が残る。 | [decision log](../../../decision-log.md) |
| task-49 の履歴行 | `State(initialValue:)` が View 再生成ごとに全件導出する。表示件数は最大 20、正しさへの影響はないが、State 初期値を空にして `.task(id:)` に一本化する候補。 | [decision log](../../../decision-log.md) |
| task-46 のシェブロン | 長い思考要約では開閉シェブロンが右端へ寄り、短い要約では見出し直後になる。 | [visual-task-46](../../../docs/agent-output/visual-task-46.md) |
| task-45 の未検証 | 240pt ペインを実測できなかった。花名と同じ文字列・空欄への UI rename も未実施。 | [decision log](../../../decision-log.md)、[visual-task-45](../../../docs/agent-output/visual-task-45.md) |
| task-50 の英語 | 英語起動時も設定・管理画面に日本語が残る混在を観測した。 | [decision log](../../../decision-log.md)、[visual-task-50-r3](../../../docs/agent-output/visual-task-50-r3.md) |
| task-47 の未検証 | 実イベント追記の画面表示、最新・過去コマンドの実行中補足の差、タブ・行末空白・CR の画像上の判別は未検証。 | [decision log](../../../decision-log.md)、[visual-task-47](../../../docs/agent-output/visual-task-47.md) |
