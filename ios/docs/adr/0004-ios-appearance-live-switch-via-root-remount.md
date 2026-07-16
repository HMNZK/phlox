---
status: active
last-verified: 2026-07-14
---

# ADR 0004: iOS 外観を rootContent の再マウントで即時反映する

> **このファイルの役割**: iOS のシステム／ライト／ダーク切替を再起動なしで反映する方式と、そのトレードオフを記録する。
> **書かないもの**: 設定画面の現行構成（→ architecture）や色トークンの一覧（→ specs）。

## 文脈

`DSColor.camp*` はグローバルな `ThemeStore.active` を経由して色を読む。`ThemeStore` はテーマ変更をアプリ再起動で反映する設計で、SwiftUI が色の変更を自動観測して再描画する仕組みを持たない。

今回の iOS 外観設定は、システム／ライト／ダークを再起動なしで即時反映する必要がある。一方、共有される macOS 側への影響を避けるため、`ThemeStore` 本体は変更しない制約がある。

## 決定

`AppRoot` で外観設定に対応するテーマ ID を `phlox.theme` へ同期し、`rootContent` に `.id(activeThemeID)` を付ける。テーマ ID が変わった時に `rootContent` を再マウントさせ、`ThemeStore.active` を参照する `camp*` 色を再評価することで、再起動なしの即時反映を実現する。

`system` モードでは `@Environment(\.colorScheme)` に追従して有効テーマ ID を切り替える。`.preferredColorScheme` は system では `nil`、light／dark では対応する値を `rootContent` へ適用する。

## 棄却案

- **`ThemeStore` または `DSColor` を reactive にする**: SwiftUI の観測モデルへ改修すれば再マウントを避けられるが、共有 macOS 面を含む `ThemeStore` の変更が必要であり、本 run のスコープ外。
- **外観変更後の再起動を要求する**: 設定画面からの即時反映という要件を満たさない。

## 結果

- システム／ライト／ダークの変更がアプリ再起動なしで反映される。
- system モードで OS の明暗が変わった時も `activeThemeID` が変わり、`rootContent` が再マウントされる。
- 再マウントにより、`rootContent` 以下の深い一時的な View state が失われる可能性がある。
- `.id` は `rootContent` に付き、`AppRoot` が保持する `@State` の model は再生成されない。そのため `authState` は保持され、`LaunchGate` の再認証は発生しない。
