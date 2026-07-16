---
status: active
last-verified: 2026-07-15
---

# ADR 0007: 下部タブバーから「概要（overview）」タブを廃止し3タブ構成にする

> **このファイルの役割**: wave-4 で `AppTab` から `.overview` を除去し、下部タブを sessions/settings/usage の3本にした判断を記録する。ADR-0006 の一部（4タブ構成・overview 再選択トグル）を差し替える。
> **書かないもの**: 独自タブバー（`Button` 群）を採用した理由そのもの（→ [adr/0006](0006-appshell-custom-tab-bar.md)、そちらは有効のまま）。現行のタブ構成（→ [architecture/overview.md](../architecture/overview.md)）。

## 文脈

ADR-0006 は「下部固定タブバー（4タブ: セッション一覧／俯瞰／設定／Usage）。俯瞰タブを再選択したら grid⇔single 表示を反転する」という wave-2 時点の要件を前提に、独自タブバー実装を採用した。wave-4 でユーザーから「概要（俯瞰）タブを廃止する」明示要望があり、下部タブを3本（セッション一覧／設定／Usage）へ縮小することになった。

## 決定

`AppTab`（`ios/Packages/PhloxKit/Sources/Features/AppShell/AppShellViewModel.swift`）から `.overview` ケースを除去し、`case sessions, settings, usage` の3値にした（コミット `8383311` task-1）。連動して:

- `AppShellViewModel.selectTab(_:)` から「更新前後とも `.overview` なら `toggleMode()` を呼ぶ」再選択トグル分岐を削除し、単純な `selectedTab = tab` に戻した。`handleTabTap` は変わらず薄いラッパー。
- `AppRoot.appTabBar` から「概要」ボタン（`square.grid.2x2` アイコン）を削除。
- `AppShellViewModel` は引き続き `overview: SessionsOverviewViewModel` を保持するが、タブ UI からは到達不能になった。`Features/SessionsOverview`（`SessionsOverviewView`/`SessionsOverviewViewModel`/`OverviewMode` 等）のソース自体は**削除していない**（デッドコードとして残置。物理削除は本 run のスコープ外）。
- wave-2 の凍結受け入れテスト `Wave2AppShellAcceptanceTests.tabOrderIsFrozenToFourTabs` と overview 再選択トグルの3件は「4タブ」「トグル」を主張しwave-4 と矛盾するため削除（PM 裁定、decision-log.md task-1 波及テスト処理）。新たに `Wave4TabAndNavigationAcceptanceTests.overviewTabRemovedFromAppTab`（`AppTab.allCases == [.sessions, .settings, .usage]`）を凍結受け入れテストとして追加した。

## 結果

- 下部タブは sessions/settings/usage の3本（宣言順）で固定。
- 俯瞰（grid⇔single）機能は UI から到達できない状態で `Features/SessionsOverview` に残る。再利用や物理削除の要否は follow-up。
- ADR-0006 の「独自 `Button` タブバー」という実装方式の決定自体は有効のまま（本 ADR が差し替えるのはタブ数・再選択トグルの部分のみ）。

## 却下した代替案

- **`.overview` ケースを残し UI からのみ隠す**: `AppTab.allCases` を含むタブ順序の凍結テストがそのまま「概要タブが存在する」実装を許容してしまい、ユーザー要望（廃止）を型レベルで保証できないため却下し、ケース自体を削除した。
