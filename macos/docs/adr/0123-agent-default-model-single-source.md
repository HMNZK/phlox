---
status: accepted
last-verified: 2026-07-26
---

# ADR 0123: エージェント既定モデルの正本を AgentDomain の `AgentModelCatalog.defaultModel(for:)` に一元化する

> **このファイルの役割**: モデル一覧と「既定でどれを選ぶか」の正本をどこに置くか、Claude の既定を何にするかの決定理由。
> **書かないもの**: live 取得の仕組み・現行の配線（→ [architecture/agent-model-catalog.md](../architecture/agent-model-catalog.md)）、live カタログ採用そのものの決定（→ [ADR 0122](0122-live-agent-model-catalog.md)）。

## 文脈

ADR 0122 で spawn 前のモデル一覧を CLI から live 取得するようにしたところ、**同じ「既定モデル」が面ごとに別々のコードで決まっている**ことが露見した。

- macOS UI（`DashboardFeature`）は `defaultCursorSpawnAgentModel` などの独自定数を持ち、Cursor は `composer-2.5`、Claude は `opus` を既定にしていた。
- モバイル向け制御 API（`ControlServer`）は一覧の `.first` を返していた。実際の `cursor-agent models` は**先頭が `auto`**、`claude --bare -p "/model"` は先頭が `sonnet` である。
- 結果として **API = auto / macOS UI = composer-2.5**、**API = sonnet / macOS UI = opus** と本番で食い違う。ユーザーから見ると「Mac で選んだ既定」と「スマホで spawn したときの既定」が別物になる。

さらにカタログ型 `ControlModelOption` は `ControlServer`（HTTP サーバ層）にあり、macOS UI 側がモデル一覧を読むには UI 層からサーバ層へ依存する形になっていた。

## 決定

1. **カタログと既定規則を `AgentDomain` へ移す**。`ControlModelOption` / `AgentModelListProviding` / `AgentModelCatalog` を `AgentDomain`（macOS・iOS 両方が共有するドメイン層 → [ADR 0001](0001-architecture.md)）に置く。HTTP サーバと UI が互いに依存せず同じカタログを読める唯一の場所だから。
2. **既定選択の唯一の正本を `AgentModelCatalog.defaultModel(for:)` にする**。制御 API も macOS UI もこの関数だけを使う。面ごとの独自定数（`defaultCursorSpawnAgentModel` 等）は廃止する。
3. **規則は「優先 ID があればそれ、無ければ CLI の先頭」**とする。優先 ID は Claude = `opus` / Cursor = `composer-2.5` / Codex = なし。
   - **Claude を `opus` にしたのはユーザー裁定**である。現行 macOS 画面の既定が opus であり、実際に使われているのが Opus であるため、モバイル／API 側を macOS に揃えた。CLI の一覧順（先頭 = `sonnet`）に従うと macOS の既定が静かに変わってしまう。
   - Cursor の `composer-2.5` は既存の既定の維持。先頭の `auto` は Cursor のルーティングモードであって固定モデルではないため、明示的な既定としては採らない。
4. **内蔵フォールバック一覧を「実在する ID だけ」に保つ責務を明記する**。この一覧は live 取得が失敗したときにだけ使われるので陳腐化に気づきにくい。実際、Cursor の内蔵一覧は `gpt-5` / `sonnet-4.5` / `opus-4.1` という**現行 `cursor-agent models` に存在しない ID** のまま残っており、`composer-2.5` 優先の規則が内蔵カタログでは発火しなかった。`composer-2.5` / `gpt-5.3-codex` / `claude-opus-5-high` へ更新し、選定理由をコード内コメントに残す。

## 棄却案

- **API 側を `.first` のままにする**: CLI の一覧順が変わるだけで既定が動く。順序は CLI の実装都合であり、Phlox の仕様ではない。
- **Claude の既定を `sonnet`（CLI の先頭）に揃える**: macOS 画面の既定が静かに opus から sonnet へ変わる。ユーザーが実際に使っているのは Opus であり、明確な劣化。
- **`ControlModelOption` を `ControlServer` に残して UI から参照する**: UI 層 → HTTP サーバ層という逆向きの依存が生じる。

## 結果

- `LiveModelCatalogWhiteboxTests` に、opus を含むカタログでは `defaultModel(for: .claudeCode) == "opus"`、含まないカタログでは先頭に落ちることを検証するテストを置いた。優先分岐を外すと赤くなることを変異試験で確認済み。
- `ControlModelOption` は synthesized `Codable` に切り替えたが、プロパティ名が凍結ワイヤキー（`id` / `displayName`）と一致するため JSON 形状は不変。`Task5ModelHandlerTests` が形状を検証する。
- 内蔵フォールバック一覧の鮮度は**テストでは守れない**（実在性は CLI の実出力にしか無い）。CLI 側の更新時に人が見直す前提の負債として残る。
