---
status: accepted
last-verified: 2026-09-15
---

# 0176: Control API のモデル変更を codex にも通す（2系統の経路を outcome で束ねる）

## 決定

`GET /sessions/{id}/settings` と `POST /sessions/{id}/model` を、spawn 型（Claude/Cursor）と
codex の両方で機能させる。分岐は `ChatSessionViewModel.applyControlModel(_:)` /
`controlModelChoices` に閉じ、Control 層（`ControlDashboardSupport`）は
`ControlSetModelOutcome` を HTTP status へ写像するだけにする。

- spawn 型: 従来どおり `setSpawnAgentModel`（model/permission/effort のフルスナップショット）。
- codex: `setModel(model:effort:)` → app-server の `updateThreadSettings`。
- 候補の広告（`availableModels`）は spawn 型が `AgentModelCatalog`、codex は app-server の
  `listModels` の**ライブ値**。理由: アプリ UI のモデルメニューと同じ出所であり、
  `updateThreadSettings` が実際に受け付ける集合だから。`AgentModelCatalog` の codex 値は
  CLI 起動フラグ向けで、アカウントの利用可能モデルとは一致しない。
- 突き合わせ規則も UI と同じ（`id` または `model` に一致、送信するのは `id`）。

status の写像:

| outcome | status | 契機 |
|---|---|---|
| `applied` | 200 | 適用成功 |
| `unknownModel` | 400 | 候補一覧に無い ID |
| `notReady` | 425 | codex の thread 未開始（wait-ready 前） |
| `unsupported` / `notFound` | 404 | モデル変更経路を持たない／セッション不在 |
| `failed` | 500 | 適用を試みて失敗 |

## 文脈

ADR 0085 は適用可否を `canApplySpawnAgentSettings`（= `SpawnAgentSettingsControlling` の実在）
だけで判定した。これは当時「codex はモデル変更経路を持たない」という前提に立っていたが、
実際には codex は `CodexSettingsProviding.updateThreadSettings` でライブ変更でき、
macOS アプリの UI からは変更できていた。つまり 0085 の codex 除外は仕様ではなく配線漏れで、
Control API だけが2系統のうち1系統しか見ていなかった。

## 結果

- codex セッションでも settings が `selectedModel` / `availableModels` を返し、
  POST /model が 200 になる（ADR 0085 の「codex は 200 + 空配列」は本 ADR で置き換わる）。
- **spawn 型でも未知モデル ID は 400 になる**（従来は 200 で黙って適用していた）。GET が
  広告する集合と POST の受理集合を一致させるための意図的な挙動変更。
- spawn 時の model 適用（`POST /sessions` の `model`）は従来どおり**1回だけ試す**。codex は
  thread 未開始で `.notReady` になるため実質適用されない。リトライ・待機は入れない
  （spawn 経路に待ちを持ち込むより、wait-ready 後に `POST /model` を呼ぶ方が単純で確実）。
- `normalizedSpawnModel` の「カタログに無い ID は silently nil」は据え置く。ここを 400 に
  変えると `POST /sessions` のワイヤ契約が変わり、凍結テストの範囲を越えるため。

## 却下した代替案

- codex の候補を `AgentModelCatalog` から出す: UI と出所が食い違い、広告したモデルを
  app-server が受け付けない乖離が起きる。
- spawn 時 model の適用をリトライ/遅延させる: spawn 応答の待ち時間が伸び、失敗時の意味も
  曖昧になる。`wait-ready` → `POST /model` の既存手順で足りる。
