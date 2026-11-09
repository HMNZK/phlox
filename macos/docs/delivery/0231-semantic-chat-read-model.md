---
status: in-progress
date: 2026-11-10
---

# 長い会話のカードと入力履歴

## 設計と範囲

[ADR 0231](../adr/0231-semantic-chat-read-model.md) に沿って、意味を確定した会話・カード詳細の有限取得、本文から独立した入力履歴、直接移動を追加する。対象は実行サービスの読取契約、索引、projection、カード・履歴・グリッド・呼び戻し・巻戻し、接続能力、検証。元の会話ログや保存形式は変えない。

作業ブランチ `chat-card-live-state-20261109`。開始 HEAD `4e58a2b2`。記録 `.verification/semantic-chat-read-20261110/`。以前の状態・時計修正の記録は [0230](0230-agent-status-card-live-state.md)。

## 未完了

実装、正しさ・応答上限の検査、Release 前後性能比較、隔離実アプリ、全体品質ゲート、独立レビュー。実行中の Release には反映しない。
