---
status: active
last-verified: 2026-07-29
---

# エージェントモデルカタログ（spawn 前のモデル一覧・現行構造）

> **このファイルの役割**: Claude / Cursor / Codex の選択可能モデル一覧を「今どうやって取得し・どこに保持し・誰が読むか」。
> **書かないもの**: なぜ live 取得にしたか（→ [ADR 0122](../adr/0122-live-agent-model-catalog.md)）、なぜ既定を一元化したか・Claude が opus か（→ [ADR 0123](../adr/0123-agent-default-model-single-source.md)）、なぜ表示名を CLI から取るか（→ [ADR 0140](../adr/0140-claude-model-display-names-from-cli.md)）。

## 全体像

```
起動（CompositionRoot）
  └─ LiveAgentModelProvider ──(CLI 実行)── claude / cursor-agent / codex
        └─ CachingAgentModelProvider（TTL 300 秒）
              └─ AgentModelCatalog.configure(provider:)
                    └─ Task.detached { 300 秒ごとに refresh() }
                          └─ AgentModelCatalog（プロセス内スナップショット・NSLock）
                                ├─ 同期読み取り: ControlServer（GET /agents/{kind}/models 等）
                                └─ 同期読み取り: macOS UI（SessionSpawnService ほか）
```

## 構成要素

| 型 / 場所 | 役割 |
|---|---|
| `AgentDomain/AgentModelCatalog.swift` — `ControlModelOption` | `{id, displayName}`。synthesized `Codable` のキーが凍結ワイヤ形状と一致する（iOS 側 `PhloxModelWireContract` と一字一句同じ） |
| 同 — `AgentModelListProviding` | 一覧の供給元プロトコル。CLI / JSON-RPC のような重い処理はここに閉じ、リクエストハンドラの同期パスでは走らせない |
| 同 — `AgentModelCatalog` | プロセス全体で**同期読み取り可能な**スナップショット。`models(for:)` / `builtinModels(for:)` / `defaultModel(for:)` / `refresh()` / `kindsUsingFallback()` |
| `ControlServer/AgentModelProviders.swift` — `LiveAgentModelProvider` | CLI を実際に叩く実装。`ClaudeModelListParser` / `CursorModelListParser` が出力をパースする |
| 同 — `CachingAgentModelProvider` | TTL 300 秒の actor キャッシュ |
| `App/CompositionRoot.swift` | 起動時に provider を配線し、300 秒周期の refresh タスクを起こす。フォールバック中の kind を warning ログに出す |

## 取得コマンドとパース

| kind | コマンド | パース |
|---|---|---|
| `claudeCode` | ① `claude --bare -p "/model" --output-format json` ② alias ごとに `claude --bare --model <alias> -p "/model" --output-format json` | ① 応答テキスト中の `Available: a, b, c` を分解して alias 一覧を得る（API 呼び出しなし・課金 0）。`default` / `opusplan` / `[1m]` 付き alias も**除外しない**（CLI 自身が選択肢として提示しているため → ADR 0122）。② 各 alias の `Current model: <表示名> (effort: …)` から表示名を取る（→ ADR 0140） |
| `cursor` | `cursor-agent models` | ヘッダ行・空行・不正行を捨て、`<id> - <displayName>` 形式と素の ID を拾う |
| `codex` | `codex` の app-server | ADR 0085 / 0087 で「空カタログ」としていたものを ADR 0122 で解禁 |

Claude の表示名解決（②）は alias ごとに 1 プロセスを並列に起動し、`claudeOptions` が一覧順を保って組み直す。失敗した alias は**その alias 文字列を表示名にして残す**（選択肢を落とさない・一覧全体を失敗させない）。複数の alias が同じ製品名に解決された場合（`best` と `fable`、`sonnet` と `sonnet[1m]` 等）は、衝突した行にだけ `Fable 5 (best)` のように alias を添えて区別する。

`LiveAgentModelProvider.childEnvironment(base:)` が子プロセスへ渡す環境を組む。GUI アプリからの起動では `PATH` が最小限になるため明示指定が要り、`cursor-agent` のラッパーは `set -u` のため `HOME` が無いと全損する。`USER` / `LANG` は通常の CLI と同じ identity / locale を保つために渡す。

## フォールバックと観測

- CLI 取得が失敗した kind は `builtinModels(for:)`（コード内蔵の固定一覧）へ落ちる。**内蔵一覧は live が死んだときにしか使われないので陳腐化に気づきにくい**。実在する ID だけを置くこと（→ ADR 0123 §4）。Claude の内蔵一覧は alias だけを持ち、表示名も alias と同値にする（バージョン名を書くと古びる → ADR 0140）。Codex の内蔵一覧は空。
- フォールバック中の kind は `kindsUsingFallback()` で読め、`CompositionRoot` が起動ログに warning を出す。
- `configure(provider:)` は**直前の完了スナップショットを保持する**。provider を差し替えている最中に同期読み取り側が一瞬カタログを失わないため。`generation` カウンタで、差し替え中に走っていた古い refresh の結果を捨てる。

## 消費側

| 消費側 | 経路 |
|---|---|
| モバイル（spawn 前） | `GET /agents/{kind}/models` → iOS `Features/SessionDetail` のモデルピッカー |
| モバイル（既存セッション） | `GET /sessions/{id}/settings` の `availableModels` |
| macOS UI | `SessionSpawnService` 経由で spawn 時の既定・選択肢に使う |

いずれも `AgentModelCatalog.defaultModel(for:)` を**唯一の既定規則**として読む（→ ADR 0123）。
