---
status: superseded
superseded-by: 0113-subagent-live-tool-merge-and-two-way-source-rule.md
last-verified: 2026-07-21
---

> **〔0113 で supersede〕** 本 ADR は「ライブのツール2重化」を前提に選択規則側で症状を塞いだ対症療法だった。
> 実行中は `outputFile` が未着で parsed を選べないため2重表示が残る。0113 でライブ側を
> 「1 ツールコール = 1 セル」に直し、`.completed` 特例と件数タイブレークは撤去した。

# ADR 0106: 完了サブエージェントの transcript は parsed（永続）を優先する

## 文脈

`ChatSubAgentModel.transcript(for:)` は、サブエージェント別ペインに表示する transcript を2ソースから選ぶ
（architecture/chat-subagent-display.md「transcript の 2 ソースと選択」）:

- **ライブ**: stdout stream 由来。永続化されない。
- **parsed**: `SubAgentRef.outputFile`（子 JSONL）を `SubAgentTranscriptLoader.parse` したもの。

当初の選択規則は「片方だけ reasoning を持つ → reasoning を持つ側（ADR 0025 由来）／それ以外 →
`parsed.count >= live.count ? parsed : live`（＝**項目数の多い方**）」だった。

実データ検証で、完了済みサブエージェントの右ペインに「①ツールの2重表示 ②ツールの合間の中間ナレーション欠落」が
起きることを確認した（例: ツール31件が `×62` 表示、途中ナレーション9件が非表示）。切り分け:

- ライブは各ツールを **tool_use（inline assistant）と tool_result（inline user）の両方**から
  `.subAgentActivity(.tool)` として生む → ツール件数が実数の約**2倍**に水増しされる。
- ライブ stdout はサブエージェントの**中間ナレーション text を運ばない**（ツール活動と最終レポートのみ。
  最終レポートは launcher の tool_result 経由で `-output` チャネルに届く）一方、parsed は tool_use+tool_result を
  1セルにマージし中間ナレーションも保持する。
- 結果、2重化で件数が膨れたライブ（ナレーション欠落）が、内容の richer な parsed に**件数比較で不当に勝つ**。
  ライブは永続化されないため、アプリ再起動後は parsed が選ばれナレーションが復活する＝データは失われていないが、
  ライブが存在する間は表示されない。

## 決定

**完了済み（該当 `SubAgentRef.status == .completed`）かつ parsed が読める場合は、parsed を優先する。**
件数タイブレークは実行中（未完了・ストリーミング途中）のフォールバックとしてのみ残す。選択順（順序が重要）:

1. parsed が無ければ live（既存 guard、不変）。
2. 片方だけ reasoning を持つ → reasoning を持つ側（ADR 0025 由来、不変）。
3. **（本 ADR）`status == .completed` なら parsed。**
4. それ以外（実行中）→ `parsed.count >= live.count ? parsed : live`（既存、不変）。

- **reasoning 優先（2）を（3）より前に置く**ことで、暗号化 reasoning のため parsed に reasoning 本文が無く
  ライブだけが reasoning を持つ完了ケースでは、従来どおりライブを選び reasoning を失わない（ADR 0025 §
  reasoning 優先の非回帰）。
- `.completed` のみ特別扱いし、`.failed` 等は件数タイブレークのまま（部分的な失敗 transcript で parsed が
  必ずしも権威とは限らないため保守的に据え置く）。
- 選択の切替のみで、**表示・保存する transcript 本文は無加工**。

## 棄却案

- **件数メトリクスの2重化補正（ライブのツールを de-dup してから比較）**: 複雑で fragile。かつ実行中も parsed が
  中間ナレーションを持つとは限らず効果が不確実。完了＝権威シグナルへの置換の方が最小差分で確実。
- **常に parsed を優先**: 実行中はまだファイルが不完全なことがあり、ストリーミング途中の live 表示を失う。
  完了に限定して回避。

## 結果

- 完了サブエージェントの右ペインで、ツールがマージ済み件数（実数）で表示され、ツールの合間の中間ナレーションが
  表示される。ライブ存在中／再起動後で表示が一致する。
- reasoning 優先は不変で回帰なし。実行中のストリーミング表示も不変。
- 受け入れテスト `SubAgentCompletedPrefersPersistedNarrationAcceptanceTests`
  （`completedSubAgentPrefersPersistedNarrationOverDoubledLiveTools`）で契約を凍結。既存
  `SubAgentReasoningPreferenceAcceptanceTests` は不変で green。

現行の構成・データフローは architecture/chat-subagent-display.md を参照。ライブのツール2重化そのものは
本 ADR の対象外（完了時は parsed 採用で回避される）。
