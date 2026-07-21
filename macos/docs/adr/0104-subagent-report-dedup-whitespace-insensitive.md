---
status: active
last-verified: 2026-07-21
---

# ADR 0104: サブエージェント完了レポートの dedup を空白非依存にする

## 文脈

ADR 0025 §7 は、サブエージェントの完了レポートが複数チャネル（inline 最終テキスト
`.subAgentActivity(.message)` ／ 完了 tool_result `-output` ／ 完了 recap summary `-summary`）で
同一本文として届く事実（§3）に対し、`ChatSubAgentModel.appendSubAgentTranscriptItem` で
「**新規 or 既存の一方が完了レポート系 id（`-output`/`-summary`）で同一本文**」なら追加しない、という
dedup を導入した。当初の一致判定は `trimmingCharacters(in: .whitespacesAndNewlines)` 後の**完全一致**だった。

実運用で「完了後にサブエージェントの最終レポートが右ペインで2回表示される」バグが観測された。切り分け:

- 完了したサブエージェントには必ずレポート系チャネル（`-summary`/`-output`）のアイテムが1つ存在する。
- inline 側とレポート系側が byte 一致していれば dedup が必ず片方を落とす（1回表示）。
- 2回見えている ⇒ **inline とレポート系の本文が byte 一致していない**。両者は同一レポートだが、
  inline は複数 text ブロックを区切り無しで連結（`existingText + text`）する一方、`summary` は別経路の
  整形済み文字列のため、**改行↔空白・連結時の区切り欠落**といった整形差が生じ、完全一致をすり抜けていた。

## 決定

dedup の本文一致判定を、**空白（スペース・タブ・改行を全て）除去した比較**に変える
（`whitespaceStrippedForDedup`）。これにより整形のみが異なる同一レポートを1件に畳む。

- **レポート系チャネル制約は維持**する（`newIsReportChannel || Self.isCompletionReportId(existingId)`）。
  レポート系が絡まない inline 同士の正当な同一本文は従来どおり両方残す（ADR 0025 §7 を回帰させない）。
- **空白除去は dedup 比較専用**にとどめ、transcript に保存・表示する item の本文は無加工にする
  （整形を破壊しない）。
- 空白除去後が空になる本文は、従来の trim-empty と同様に dedup 対象外（append する）。

本 ADR は ADR 0025 §7 の一致判定を精緻化するもので、§7 の他の決定（レポート系チャネル制約・
inline 同士は両方残す）は不変。

## 棄却案

- **全 agentMessage を空白非依存で dedup（レポート系制約を外す）**: ADR 0025 §7 が退けた「正当に同じ文を
  複数回出す inline を巻き添えで落とす」を再発させる。レポート系制約を残して回避。
- **表示本文自体を空白正規化して保存**: 整形（改行・インデント）を破壊し可読性を損なう。比較専用にとどめた。
- **`collapse-to-single-space`（空白を単一スペースに畳む）**: inline の「区切り欠落」ケース
  （"…である。対策は…" vs "…である。 対策は…"）で、空白が全く無い側と一致しないため取りこぼす。
  全除去にして両方向の整形差を吸収する。

## 結果

- 完了後の最終レポートの二重表示を解消。整形差（改行↔空白・区切り欠落）を吸収しつつ、
  本文が実質（非空白）で異なるレポートは過剰 dedup せず両方残す。
- 受け入れテスト `SubAgentReportFormattingDedupAcceptanceTests`（`newlineVsSpace` /
  `missingSeparator` / `genuinelyDifferent`）で契約を凍結。既存 `SubAgentOutputDedupAcceptanceTests`
  （byte 一致 dedup・§7 の両方残す）は不変で green。

現行の構成・データフローは architecture/chat-subagent-display.md を参照。
