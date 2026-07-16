---
status: active
last-verified: 2026-07-15
---

# ADR 0006: 下部タブバーは独自実装とし SwiftUI TabView を採用しない

> **このファイルの役割**: `AppRoot` の下部固定タブバー刷新で、標準 `TabView` ではなく独自タブバー（アイコン＋下ラベルの `Button` 群）を採用した理由を記録する。
> **書かないもの**: 現行の AppShell 構成（→ [architecture/overview.md](../architecture/overview.md)）。
>
> **追記 (2026-07-15)**: 本 ADR が前提とした「4タブ構成」「俯瞰タブ再選択での grid⇔single トグル」は wave-4 で `.overview` タブ廃止により置き換えられた。詳細は [ADR 0007](0007-remove-overview-tab.md)。**独自 `Button` タブバー実装を採用したという決定自体（本 ADR の核）は有効のまま**。

## 文脈

要件は「下部固定タブバー（4タブ: セッション一覧／俯瞰／設定／Usage）。俯瞰タブを**再選択**したら grid⇔single 表示を反転する」。初期実装（コミット `09f99c0`）は SwiftUI 標準 `TabView(selection:)` ＋ `.tabItem` で構築し、`AppShellViewModel.selectTab(_:)` を `Binding` の `set` クロージャ経由で呼んでいた。

## 決定

`TabView` を撤去し、`VStack`（コンテンツ＋`Divider`＋タブ行）による独自タブバー（`AppRoot.appTabBar`）に置き換えた（コミット `65f425a`）。タブ行の各 `Button`（アイコン＋下ラベル）の action は `AppShellViewModel.handleTabTap(tab)` を直接呼ぶ。

- **なぜ**: `TabView` が同一タブの再タップでも `selection` Binding の `set` クロージャを発火するかは SwiftUI の内部実装・OS バージョンに依存し、実機確認なしに決定的な挙動を保証できなかった（凍結受け入れテストのコメントに「OS バージョン差の実機確認が必要」と明記されていた）。独自 `Button` は標準のタップジェスチャで、選択状態に関わらず**必ず** action クロージャへ到達するため、再選択検出（俯瞰タブ再タップでの反転）をコードレベルで決定的にできる。
- ユーザー要件「アイコン＋下ラベル」の見た目にも直接一致する（`TabItem` のスタイル制御より自由度が高い）。

`AppShellViewModel.selectTab(_:)` 自体のロジック（更新前の `selectedTab` を読み、`.overview → .overview` の遷移だけ `toggleMode()` を呼ぶ）は変更していない。View 側の入力経路だけを OS 依存 Binding から自前 `Button` へ置換した。

## 結果

- 白箱テスト `Wave2AppShellWhiteboxTests.repeatedOverviewTapsAlwaysReachTheShellSelectionPath` で同一タブ連打時の確定的な grid⇔single 反転を固定。
- `AppTab.allCases`（宣言順 `.sessions/.overview/.settings/.usage`）の4タブ構成は凍結受け入れテスト `Wave2AppShellAcceptanceTests.tabOrderIsFrozenToFourTabs` で固定。
- **積み残し（phase-4 事項）**: 独自タブバーはネイティブ `TabView` が持つタップフィードバック・遷移アニメーションを持たない。実機での操作感・視覚的な違和感の有無は未確認。

## 却下した代替案

- **`TabView` のまま実機で OS バージョン別の再タップ挙動を検証してから決める**: 実機なしでは判断できず開発ループが止まるため却下し、決定的な自前実装を優先した。
