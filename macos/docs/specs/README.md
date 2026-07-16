---
status: active        # active | completed | superseded | archived
last-verified: 2026-07-08
---

# specs/

**役割（ここにしか書かない）**: 要件・仕様（FR/NFR・受け入れ基準・用語/ドメイン）

**書かないもの**: 設計の詳細・手順（→ architecture/・guides/）

**Diátaxis**: Reference

**命名**: 小文字 kebab-case・ASCII・`.md`（索引のみ `README.md`）。順序ありは `NNNN-kebab.md`。

## 現在あるファイル

| ファイル | status | 内容 |
|---|---|---|
| `agent-registry-refactor.md` | completed | 設定駆動レジストリ化（`AgentDescriptor`/`AgentRegistry`）の設計ゴール。歴史的ロードマップ（当時7 CLI 前提・現行3種） |
| `amazon-q-integration.md` | superseded | Amazon Q Developer CLI 統合仕様。ベンダー撤退により撤去済み（2026-06-11） |
| `custom-agents-json.md` | active | ユーザー定義 CLI（JSON）対応の設計ゴールと利用手順 |
| `design-system-ios.md` | active | iOS コンパニオンアプリ向けデザインシステム拡張計画（Draft） |
| `e2e-test-design.md` | active | Phlox E2E テスト設計書（Layer A/B の戦略・シナリオカタログ） |
| `gemini-cli-integration.md` | superseded | Gemini CLI 統合仕様。ADR 0041 で削除済み |
| `goose-integration.md` | superseded | Goose 統合仕様。ADR 0041 で削除済み |
| `grid-view-layout.md` | active | グリッドビューの固定 N×N・自由配置・セル結合の要件（FR/NFR・受け入れテスト。決定は ADR 0084） |
| `liquid-glass-ui.md` | active | Liquid Glass UI 刷新の実装プラン（ADR 0019・実装未着手） |
| `localization.md` | active | アプリ内多言語化（日本語/英語ライブ切替）の方針と追加手順 |
| `opencode-integration.md` | superseded | opencode 統合仕様。ADR 0041 で削除済み |
| `rearchitecture-refactoring-plan.md` | active | コードベース全体のリアーキテクチャリング・リファクタリング計画（Phase 0〜7・WP 分割ドラフト） |
| `review-remediation.md` | active | Codex レビュー指摘（重大+中）の修正仕様 |
