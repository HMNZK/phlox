---
status: active
last-verified: 2026-07-11
---

# ADR 0077: サブエージェント transcript のストリーミング断片を itemId で結合する

> **このファイルの役割**: 「サブエージェント実行中にそのドロワーを開くと CPU 暴走する」の根本対策として、断片ごとの item 増殖を止める結合方式を決める。
> **書かないもの**: 現行のデータフロー・stableId の詳細（→ `architecture/chat-subagent-display.md`）。

## 文脈

サブエージェント経路（`parent_tool_use_id` 付き assistant イベント）は、メインチャット経路と同じ content block の断片（delta 相当）を受け取るのに、メイン経路の itemId マージ（`appendDelta`）に相当する結合を持たなかった。`ChatSubAgentModel` は `.message`/`.reasoning` 断片を受けるたびカウント連番 id で新規 `ChatItem` を append し、ストリーミング1断片=1 item で transcript が無制限に膨張。ドロワー表示中は `@Observable` の mutate ごとに `ForEach(transcript)` が高頻度・大規模再描画され、CPU 暴走としてユーザーに観測された（run `subagent-session-cpu`・`docs/delivery/0042-subagent-session-cpu-worklog.md`）。

## 決定

**断片の発生源（emitter）で安定 itemId を付与し、モデル側で同一 `(toolUseId, kind, itemId)` へ upsert 結合する**（2026-07-11）。

- `NormalizedChatEvent.subAgentActivity` に `itemId: String?` を追加（`StructuredChatKit/StructuredChatTypes.swift`。公開 enum のため依存パッケージを同 run 内で追随）。
- `ClaudeChatClient+SubAgentContent.swift` が message id × content 種別から安定 itemId を導出して運ぶ（tool_use の prompt 入力由来 `.prompt` は itemId なし）。
- `ChatSubAgentModel.appendMergeableSubAgentActivity` が itemId 非 nil の `.message`/`.reasoning` を stableId `"\(toolUseId)-\(kind)-\(itemId)-stream"` で結合（text 追記）。棄却は厳密な `text.isEmpty` のみ（空白断片は保存）。itemId nil は従来どおり個別 item。

## 棄却案

- **SubAgentDrawerView の仮想化・描画スロットリング**: 表示側の対症療法。item 増殖という根本原因（データ量 O(断片数)）が残り、非表示時のメモリ膨張も解けない。
- **完全文前提の置換（断片でなく全文が来ると仮定）**: 断片/全文のどちらが来るかはイベント個体差があり、全文前提は断片個体で本文欠損を生む。upsert 結合はどちらでも壊れない。

## 結果

- 断片 N 件が O(メッセージ境界数) の item に収まり、ドロワー表示中の再描画コストがイベント頻度に対し一定化する。
- 凍結受け入れテスト: `AcceptanceSubAgentTranscriptMergeTests`（SessionFeature）・`AcceptanceSubAgentActivityItemIdTests`（ClaudeAgentKit）。
- 実機での CPU 収束のランタイム検証は統合検証（フェーズ4）で実施する（`swift test` green は描画ハングの非存在を保証しないため。CLAUDE.md の runtime 検証原則）。
