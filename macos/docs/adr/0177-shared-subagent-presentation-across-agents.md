---
status: accepted
last-verified: 2026-09-29
---

# 0177: Claude / Codex / Cursor のサブエージェント表示を共通化する

## 決定

サブエージェントの表示は、Claude の既存 UI を共通部品として使う。

- 実行中の切替は `SubAgentStrip` / `SubAgentStripRow` に集約する。
- 会話内の履歴リンクは `ChatItem.subAgentMarker` / `SubAgentMarkerCell` に集約する。
- 詳細は `SubAgentDrawerView` に集約する。Codex は読み取り専用なので追加指示欄を表示しない。
- 完了したサブエージェントは上部の帯から外し、会話内マーカーから引き続き閲覧できる。
- Codex のプラン表示は会話内に残す。Codex 固有の子一覧カードとグリッド上部の重ね表示は廃止する。
- Codex の thread 一覧・親 thread 判定・詳細読込・停止は `CodexSubAgentState` と `ChatSessionViewModel` に残す。表示 ID は Codex の thread ID と名前空間を分け、ユーザー向け文言に thread ID を使わない。
- Cursor も同じ表示部品を通す。ただし Cursor のサブエージェント通知が無い場合は空のままにし、子や履歴を推測で作らない。

Codex の詳細は、共有ドロワーで既存 `thread/read(includeTurns: true)` の本文を表示する。Codex の「停止」は thread が停止可能な間だけ共有 strip 行に出し、実際の停止要求は既存 `stopCodexSubAgent` を通す。

## 文脈

Claude は上部の切替、会話内マーカー、右側の詳細ペインでサブエージェントを扱っていた。一方、Codex は独自カードを会話内に出し、さらにグリッドでは同じカードを上部へ重ねていたため、表示が二重になっていた。別々の UI は状態差を増やし、子 thread の詳細や完了後の閲覧方法も揃わなかった。

Codex の `thread/list` / `thread/read` / `turn/interrupt` は親 thread と child thread の対応を検証する既存経路を使う。UI 共通化のために履歴を親 transcript へ統合したり、Codex 状態を Claude の stream 状態へ移したりはしない。

## 結果

- Claude と Codex は同じ切替・マーカー・詳細表示を使い、Codex child は専用カードと二重表示を持たない。
- Codex child の本文は詳細ペインに隔離され、親会話には閲覧用マーカーだけが残る。実行中の停止も従来の Codex child 専用 API 経路を維持する。
- Cursor の通知が実装されるまでは共有部品が空表示になる。通知対応は別のデータソース実装として扱う。
- Codex の thread 名や ID が表示名として漏れないよう、表示名が無い場合は汎用名を使う。読み込み失敗は ID を含まない案内を表示する。

## 却下した代替案

- Claude と Codex のバックエンド状態を一つのモデルへ統合する: Codex には親 thread 識別、履歴取得、停止確認の契約があり、UI 共通化のための状態統合は必要ない。
- Codex 専用カードを残して見た目だけ寄せる: 切替・完了後の閲覧・詳細の重複した経路を引き続き保つことになる。
- Cursor の子 thread を推測して表示する: 現在通知の根拠が無く、実在しない子や履歴を作る危険がある。
