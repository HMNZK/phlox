---
status: active
last-verified: 2026-07-15
---

# ADR 0005: モバイル wave-2 ワイヤ消費とアカウント使用量／ターン使用量の型分離

> **このファイルの役割**: 契約 [`../specs/mobile-api-extensions-contract.md`](../specs/mobile-api-extensions-contract.md) §7（spawn 前モデル選択・プロジェクト情報・アカウント使用量）の iOS 側消費で採った設計判断を記録する。
> **書かないもの**: サーバー側実装判断（→ [`macos/docs/adr/0087`](../../../macos/docs/adr/0087-mobile-wave2-wire-extensions.md)）／現行画面構成（→ [architecture/overview.md](../architecture/overview.md)）。

## 文脈

新規タスク画面でのモデル選択（spawn 前）、セッション一覧のプロジェクトグルーピング、Usage 画面（アカウント単位の CLI 使用量）の実装にあたり、既存の `TurnUsage`（1ターンのコスト・コンテキスト使用量）と新設の `CLIUsage`（アカウント全体のクォータ消費）が意味的に全く異なるにもかかわらず「usage」という同じ語を使う衝突が生じた。また、spawn 前のモデル一覧取得・アカウント使用量取得はいずれもネットワーク失敗の可能性があり、失敗時の UX 方針を決める必要があった。

## 決定

### 1. `CLIUsage`/`UsageBucket`/`CLIUsageState` を `TurnUsage` とは別型として追加する

`PhloxCore` に `CLIUsage`（`kind`/`state`/`buckets`/`updatedAt`/`dataAsOf`）を新設し、既存の `TurnUsage`（`costUSD`/`contextUsedTokens`/`contextWindowTokens`）とは意図的に分離した。API も `cliUsage()` と `usage(sessionID:)` で明確に呼び分ける。

- **なぜ**: 「1ターンのコスト」と「アカウント全体の残量」は呼び出し元・更新頻度・表示先画面のいずれも異なる。1型に混在させると nil の意味が曖昧になり（ターン未実行で nil なのか、アカウント側データ欠如で nil なのかの判別が困難）、呼び出し側の分岐が複雑化する。

### 2. spawn 前のモデル取得・アカウント使用量取得は、失敗時に静かに空へフォールバックする

`SpawnViewModel.loadModels()` はネットワーク失敗時に画面全体をエラー状態へ遷移させず、`availableModels`/`selectedModel` を空にクリアする（Picker が自動的に非表示になる）。同様に `UsageViewModel.load()` も失敗時は `agents = []` かつ `.failed` 状態にし、画面自体は表示を続ける。

- **なぜ**: モデル選択もアカウント使用量表示も、セッション作成・チャット閲覧という主機能に対する付加情報であり、取得失敗で主機能を巻き込んで壊す理由がない。ADR 0085 の「モデル選択非対応セッションはチップ非表示」という既存の劣化パターンと一貫させた。

## 結果

- `Wave2WireDecodeContractTests` が `AgentModels`/`CLIUsage` の decode 契約と、両者が `TurnUsage` と混同されないことを凍結。
- spawn 時のモデル取得・Usage 画面の取得はいずれもグレースフルデグレード（機能非表示・空表示）に倒れ、既存のモデルチップ非表示パターンと UX 上一貫する。

## 却下した代替案

- **`TurnUsage` を拡張してアカウント単位フィールドを持たせる**: 意味の異なる2概念を1型に混在させると nil 判別が曖昧になり、却下した。
- **取得失敗時にエラーバナー／リトライ UI を表示する**: 付加情報の取得失敗で主機能の画面を煩雑にする必要はないと判断し、静かなフォールバックを選んだ。
