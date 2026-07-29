---
status: accepted
last-verified: 2026-07-29
---

# ADR 0140: Claude モデルの表示名を CLI に問い合わせて解決する（バージョン名をコードに持たない）

> **このファイルの役割**: モデルピッカーの表示名（"Opus 5" 等）をどこから得るかの決定理由。
> **書かないもの**: 現行の配線・コマンド（→ [architecture/agent-model-catalog.md](../architecture/agent-model-catalog.md)）、live 一覧そのものの採用（→ [ADR 0122](0122-live-agent-model-catalog.md)）、既定モデルの正本（→ [ADR 0123](0123-agent-default-model-single-source.md)）。

## 文脈

ADR 0122 で一覧を live 取得するようにした後も、**表示名だけはコード内の固定表**だった（`LiveAgentModelProvider.option(_:)` の `["opus": "Opus 4.8", …]`）。理由は、一覧取得に使う `claude --bare -p "/model"` の `Available:` 行が alias しか返さず、製品名・バージョンをどこにも含まないためである。ADR 0123 §4 はこれを「CLI 側の更新時に人が見直す前提の負債」として明記していた。

その負債が実際に表面化した。CLI が Opus 5 を提供しているのに、Phlox のモデル選択は **"Opus 4.8" と表示し続けた**。live 一覧は正しく `opus` を返しているので一覧・spawn は正常で、**表示だけが古い**という気づきにくい壊れ方になる。ユーザーから「なぜ Opus 5 ではなく Opus 4.8 が出るのか」と指摘されて発覚した。

## 決定

**alias ごとに `claude --bare --model <alias> -p "/model" --output-format json` を実行し、`Current model: <表示名> (effort: …)` から表示名を取る。**

- `--model <alias>` はその実行だけのモデル指定であり、保存された選択には触れない。実測で `total_cost_usd: 0` / `num_turns: 0`（API を叩かずローカル完結）。
- 末尾の `(effort: …)` はセッションの reasoning 設定であって名前の一部ではないので落とす。
- alias 分（実測 10 個）を並列実行する。既存の `CachingAgentModelProvider`（TTL 300 秒）と 300 秒周期の refresh がそのまま効くので、実行は 5 分に 1 度。実測で一覧全体の解決が 2.4 秒。
- **表示名の解決に失敗した alias は alias 文字列を表示名にして残す**。名前が取れないことを理由に選択肢を消す・一覧全体を失敗させるのは、表示の問題を機能の問題に格上げすることになる。
- **複数の alias が同じ製品名に解決されたら、衝突した行にだけ alias を添える**（`Fable 5 (best)` / `Fable 5 (fable)`）。実測で `best`→Fable 5、`sonnet[1m]`→Sonnet 5、`default`→Opus 5 (1M context) と重複するため、そのまま出すと見分けられない行がメニューに並ぶ。
- **内蔵フォールバック一覧（`AgentModelCatalog.claudeModels`）の表示名は alias と同値にする**。CLI が居ないときにしか使われない一覧にバージョン名を書けば、同じ陳腐化を別の場所で繰り返すだけである。表示は素っ気なくなるが、嘘にはならない。

## 棄却案

- **固定表を維持して人が更新する**: これが今回壊れたやり方そのもの。表示専用の表なのでテスト・型・実行時エラーのどれも陳腐化を検出できず、気づく手段がユーザーの指摘しかない。
- **一覧取得の 1 回だけで表示名も得る**: `Available:` 行に名前が無いので不可能。`Current model:` 行は現在の選択 1 つ分しか返さない。
- **alias から表示名を推測する（`opus` → "Opus"）**: バージョンが出せず（"Opus 4.8" が消えて "Opus" になるだけ）、`best` / `opusplan` / `default` のような alias は意味が伝わらない。
- **`claude --version` からバージョンを引いて名前を組む**: CLI のバージョンとモデルのバージョンは別物で、対応表を再びコードに持つことになる。

## 結果

- 表示名は CLI の更新に自動追随する。`LiveModelCatalogWhiteboxTests` に、表示名が `--model` 付き実行から得られること・重複時に alias で区別すること・解決失敗時も選択肢を落とさないことの 3 件を追加した。
- ADR 0123 §4 の「内蔵フォールバック一覧の鮮度は人が見直すしかない」は **ID の実在性についてのみ残る**。Claude の表示名はコードから消えたので、この経路での陳腐化は起きない。Cursor / Codex は元から ID をそのまま表示している。
- 代償は**プロセス起動が 5 分ごとに +10 回**（それぞれ API 呼び出しなし・課金 0）。表示名を正しく保つ手段が他に無いので受け入れる。
