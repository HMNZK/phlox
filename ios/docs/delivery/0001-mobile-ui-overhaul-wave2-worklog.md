---
status: completed
last-verified: 2026-07-15
---

# 0001: モバイル UI 刷新 wave-2（8タスク）作業ログ

> **このファイルの役割**: この run（`feature/mobile-ui-overhaul` 上の wave-2、task-1〜task-8）で何をしたかの記録・状態スナップショット。
> **書かないもの**: 恒久仕様・現行構成（→ 生成した specs/architecture/adr の各リンク先）。

## 依頼内容（4項目）

①新規タスク画面でのモデル選択 ②セッション一覧のプロジェクト・グルーピング ③下部固定タブバー（4タブ・俯瞰の grid/single 切替含む）④ライトモード完全化 ＋ Usage（アカウント使用量）タブの本実装。

## 何をしたか（task-1〜task-8）

- **task-1**（macOS ControlServer）: モバイル向けワイヤ4拡張（spawn 時 model 適用・`GET /sessions` への project 付与・`GET /agents/{kind}/models` 新設・`GET /usage` 新設）。
- **task-2**（iOS PhloxKit ネットワーク／ドメイン層）: 凍結ワイヤの消費（`AgentModels`/`SessionModelOption`、`CLIUsage`/`UsageBucket`/`CLIUsageState`、`PhloxAPI.agentModels(kind:)`/`cliUsage()`、`SpawnRequest.model`、`Session.projectId`/`projectName`）。
- **task-3**（`Features/Spawn`）: 新規タスク画面にモデル選択 `Picker` を追加（`SpawnViewModel.loadModels()`）。
- **task-4**（`Features/SessionList`）: セッション一覧をプロジェクト単位グルーピング（`SessionGrouping.grouped(from:)`・`DisclosureGroup`）し、左上ツールバーを撤去。
- **task-5**（`Features/SessionsOverview`、新規 Feature）: セッション俯瞰ビュー（`OverviewMode` grid/single 切替）。
- **task-6**（`DesignSystemIOS`）: ライトモードのナビバー chrome をテーマ連動化（`DSNavigationChrome.barColorScheme(for:)` + UIKit appearance 再適用）。
- **task-7**（`Features/AppShell` + `AppRoot`）: 下部固定タブバー（4タブ）への再構築。初期実装は SwiftUI `TabView` だったが、俯瞰タブの再選択トグルが OS 依存 Binding に依拠する点をレビューで差し戻され、独自タブバー（アイコン＋下ラベルの `Button` 群）に置き換えた（→ [adr/0006](../adr/0006-appshell-custom-tab-bar.md)）。
- **task-8**（`Features/Usage`、新規 Feature）: アカウント単位の CLI 使用量表示画面（`UsageViewModel.load()` → `cliUsage()`）。

## 生成・更新した永続ドキュメント

- [ios/docs/specs/mobile-api-extensions-contract.md](../specs/mobile-api-extensions-contract.md) §7（wave-2 の4ワイヤ）
- [ios/docs/architecture/overview.md](../architecture/overview.md)（AppShell タブ構造・新ドメイン型・4 Feature の現行構成・ライトモード chrome）
- [macos/docs/architecture/mobile-proxy.md](../../../macos/docs/architecture/mobile-proxy.md)（新規4エンドポイントの表・wave-2 節）
- [macos/docs/adr/0087-mobile-wave2-wire-extensions.md](../../../macos/docs/adr/0087-mobile-wave2-wire-extensions.md)（サーバー側設計判断）
- [ios/docs/adr/0005-mobile-wave2-wire-consumption.md](../adr/0005-mobile-wave2-wire-consumption.md)（iOS 側消費・型分離判断）
- [ios/docs/adr/0006-appshell-custom-tab-bar.md](../adr/0006-appshell-custom-tab-bar.md)（独自タブバー採用判断）

## 検証結果（run 内で実施・decision-log.md の記録に基づく）

- task-6: フル `verify.sh` green、ステージ1（persona-reviewer）pass。
- task-1: scope clean。`GET /sessions` は wire-contract 当初案（トップレベル配列）ではなく既存互換の `{"sessions":[...]}` 包装を維持する判断に修正（既存 iOS クライアント互換のため正しい判断と裁定）。
- task-7: stage-1（Claude）pass / stage-2（Codex）needs_changes → 争点2件を PM が裁定。
  - View層の自動テスト網羅欠如（stage-2 MEDIUM）は phase-4 事項と裁定（凍結純ロジック green・iOS ビルド EXIT=0・View 構造は単体テスト対象外という既存方針に基づく）。
  - overview 再選択トグルの OS 依存 Binding 依拠（stage-2 LOW）は「押したら grid/single 入替」という機能正しさに直結するため差し戻し、決定的な独自タブバー実装（コミット `65f425a`）へ修正。
- 直近コミット（5afa97a）にてビジョンテスト補完の UI テスト2件を追加。

**本蒸留作業ではテスト・ビルドの再実行は行っていない**（上記は run 内の記録の要約。フェーズ4の実施記録は decision-log.md / git log を出典とする）。

## 積み残し・phase-4（実機確認）事項

- 独自タブバー（task-7）の再選択トグルの**実機挙動**（アニメーション・タップフィードバックがネイティブ `TabView` と異なる可能性、ADR 0006 参照）。
- ライトモード（task-6）の**視覚確認**（シミュレータ/静的レビューに留まる範囲があれば実機で最終確認）。
- Face ID（wave-1 task-5 で実装済み）を含む認証まわりの実機確認。
