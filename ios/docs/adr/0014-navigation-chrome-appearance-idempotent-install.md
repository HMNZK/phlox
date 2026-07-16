---
status: active
last-verified: 2026-07-15
---

# ADR 0014: セッション一覧上部空白バグの修正として UINavigationBar appearance 再適用を冪等化する

> **このファイルの役割**: wave-5（task-4）で、セッション一覧（Projects）の上部に空白が出る症状の根本原因を「UIKit appearance のグローバル副作用が無条件に再適用されていたこと」と特定し、テーマ変更時のみ適用する冪等化で修正した決定を記録する。ADR 0004（rootContent 再マウントによる外観即時反映）と関連する。
> **書かないもの**: 外観のライブ反映機構全体（→ [ADR 0004](0004-ios-appearance-live-switch-via-root-remount.md)）。現行のナビゲーション chrome 構成（→ [architecture/overview.md](../architecture/overview.md)）。

## 文脈

セッション一覧（Projects）の上部に大きな空白ができ、タイトルや最初のグループが見えなくなることがある症状があった（常時再現ではない状態依存）。task-4.md の PM 支給仮説は2系統:

- **仮説A（有力）**: `DSNavigationChrome.installUIKitAppearanceIfNeeded` が `UINavigationBarAppearance` を作り `UINavigationBar.appearance()`（グローバル副作用）へ**無条件に**適用する。`.onAppear`/テーマ変化のたびに再適用されると、large title の高さ計算とタイミングが衝突し、一覧へ戻った時に上部が空白になりうる。
- **仮説B**: `SessionListView` の `ScrollView` にスクロール位置リセットが無く、詳細画面から戻ると以前のオフセットが残る。

原因未特定のまま padding/spacer を削る対症療法は task-4.md で明示的に禁止されていた。

## 決定

- 仮説Aを実装役が真因と確認した（`SessionListView.swift`/`SessionListViewModel.swift` は本 wave で無改変。修正は `DSNavigationChrome.swift` のみに閉じている＝仮説Bの手当ては不要だった）。
- `DSNavigationChromeAppearanceInstaller`（`NSLock` で保護した内部クラス）を新設し、直近に適用した `themeID` を保持する。`installUIKitAppearanceIfNeeded(for:)` は `themeID` が**変化した時だけ** `UINavigationBar.appearance()` への実適用を行い、同一テーマでの再呼び出しは no-op にする（`installationCount` で適用回数を外部観測可能にした `appearanceInstallationState`）。
- ADR 0004 の `AppRoot`（`.id(activeThemeID)` による `rootContent` 再マウント）と、`DSCampNavigationChromeModifier`（`@AppStorage` の `onChange` 駆動）の**2経路それぞれから同一テーマで appearance 再適用が呼ばれても**、グローバル UIKit 状態への書き込みが1回に抑えられるようにした。

## 結果

- 一覧⇄詳細の往復で同一テーマの appearance 再適用が抑止され、large title の高さ計算との衝突が解消された。
- 回帰テスト `Wave5SessionListTopBlankTests.navigationAppearanceInstallationIsIdempotent`（同一テーマの連続呼び出しで `installationCount` が増えない、テーマ変更時のみ増える）で冪等性をユニットレベルで固定。
- フェーズ4で新規 XCUITest `Wave5RegressionUITests.testListDetailRoundTripKeepsProjectsTitle`（一覧⇄詳細を2往復しても `navigationBars["Projects"]` が可視）を実走し pass。これをもって stage-1 の needs_changes（症状の因果が実行検証されていない）を解消し `done` 確定（decision-log wave-5 フェーズ4）。

## 却下した代替案

- **ScrollView のスクロール位置リセット（仮説B）を実装する**: 実装役の切り分けで真因ではないと確認されたため見送った（コード上も `SessionListView`/`SessionListViewModel` は無改変）。
- **appearance 再適用そのものを削除する**: テーマ切替時に UIKit グローバル chrome（ナビゲーションバー色等）が更新されなくなり、ADR 0004 の外観即時反映要件を壊すため却下。冪等化（変化時のみ適用）を選んだ。
