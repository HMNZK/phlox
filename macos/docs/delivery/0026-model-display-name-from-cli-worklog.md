---
status: completed
last-verified: 2026-07-29
---

# 0026: モデル選択が "Opus 4.8" のままだった問題（表示名の CLI 取得）

関連: [ADR 0140](../adr/0140-claude-model-display-names-from-cli.md) /
[architecture/agent-model-catalog.md](../architecture/agent-model-catalog.md)

## 何をしたか

「モデル選択に Opus 5 ではなく Opus 4.8 が出る」という報告の原因を特定し、表示名を CLI から
取得する方式へ変えた。一覧・spawn は元から正しく、**表示名だけがコード内の固定表**だった。

## 判ったこと

- 直接原因は `LiveAgentModelProvider.option(_:)` の `["opus": "Opus 4.8", …]`。live 取得した
  alias は必ずここを通るため、キャッシュや CLI の状態に関係なく古い名前が出る。
- 固定表だった理由は、一覧取得に使う `claude --bare -p "/model"` の `Available:` 行が alias しか
  返さないため（製品名・バージョンを含まない）。ADR 0123 §4 が既に負債として明記していた。
- 解決手段: `claude --bare --model <alias> -p "/model" --output-format json` の 1 行目が
  `Current model: <表示名> (effort: …)` を返す。API 呼び出しなし・課金 0・ローカル完結。

## 変更したもの

| ファイル | 内容 |
|---|---|
| `ControlServer/AgentModelProviders.swift` | 固定表を撤去。`ClaudeModelListParser.parseCurrentModelName` を追加し、alias ごとに `--model` 付き `/model` を並列実行して表示名を解決。失敗した alias は alias 表示のまま残す。同名に解決された alias だけ `Fable 5 (best)` の形で区別する |
| `AgentDomain/AgentModelCatalog.swift` | Claude の内蔵フォールバック一覧の表示名を alias と同値に（バージョン名を持たない） |
| `ControlServerTests/LiveModelCatalogWhiteboxTests.swift` | パーサ 1 件・provider 3 件を追加 |
| `DashboardFeatureTests/ChatSessionViewModelCharacterizationTests.swift` | 固定表の期待値（"Opus 4.8"）を、カタログ由来＋未知 ID 素通しの特性化へ更新 |
| `docs/` | ADR 0140 追加、`agent-model-catalog.md` / `claude-chat-session-lifecycle.md` を実態へ更新 |

## 検証

| 実行 | 結果 |
|---|---|
| `swift test --package-path macos/Packages/ControlServer --no-parallel` | 139 tests passed |
| `swift test --package-path macos/Packages/AgentDomain` | 234 tests passed |
| `swift test --package-path macos/Packages/DashboardFeature` | 1492 tests passed |
| `swift test --package-path macos/Packages/SessionFeature` | 723 tests passed |
| `swift test --package-path macos/Packages/AppBootstrap` | 151 tests passed |
| 実 CLI との突き合わせ（一時テストで `LiveAgentModelProvider` を実行、コミット前に削除） | 10 alias を 2.4 秒で解決。`opus → Opus 5` / `opus[1m] → Opus 5 (1M context) (opus[1m])` / `opusplan → Opus in plan mode, else Sonnet` |

**未実施**: アプリを起動しての UI 目視確認（稼働中のリリース版を落とさないため）。表示名の解決は
provider の実 CLI 実行で確認済みで、UI はその値を `AgentModelCatalog` 経由でそのまま表示する。

## 積み残し（本件と無関係の既存問題）

`swift test --package-path macos/Packages/ControlServer` を**並列既定で**走らせると、
`AcceptanceLiveModelCatalogTests` の 1 件と `Wave2ServerWireWhiteboxTests` の 1 件が落ちる。
プロセス全体で共有する `AgentModelCatalog` のスナップショットを別スイートが同時に差し替えるため
（各スイートは `.serialized` だがスイート間は並列）。`--no-parallel` では全 pass。
dev（本変更前）でも同一の 3 issue が再現することを確認済みで、本変更とは無関係。
