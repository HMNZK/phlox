---
status: accepted
last-verified: 2026-10-17
---

# ADR 0049: 下部ナビゲーションを OS 標準の TabView に戻す

> **このファイルの役割**: 段階 3 の下部ナビゲーションに OS 標準 `TabView` を採った理由と、OS ごとの作り方・未確認事項を記録する。
> **書かないもの**: 画面の受け入れ条件（→ [仕様書 3 章](../specs/redesign-2026-10.md#3-下部のナビゲーションと対応待ちバー)）、現行の構成（→ [architecture/overview.md](../architecture/overview.md)）。

## 文脈

ADR 0006 は、俯瞰タブの押し直しを検出するため独自の `Button` 群を選んだ。俯瞰タブは段階 1 で廃止され、iOS 26 では標準のガラスのタブ・タブバー上のアクセサリ・縮小動作・独立したタブ操作、iOS 18 では標準タブバーが見本に合うかを再確認することになった。

## 決定

1. セッション・設定の 2 タブは SwiftUI の `TabView` と `Tab` で作る。選択バッジ、標準のタブ表示、タブ内の `NavigationStack` を OS に任せる。
2. iOS 26 では `tabViewBottomAccessory` に対応待ち／オフライン表示を置き、`tabBarMinimizeBehavior(.onScrollDown)` を指定する。独立した新規チャット操作には `Tab(role: .search)` を使い、Binding の `nil` を下書き compose への遷移として扱う。見た目・寸法は iOS 26 の標準タブ UI に任せる。
3. iOS 18 では標準 `TabView` を維持し、対応待ち表示を `safeAreaInset` でタブバー直上へ置く。U-14 により新規チャットだけは一覧画面の大見出し右に 44pt のボタンを置く。
4. 対応待ち件数と先頭の選択は View に依存しない `SessionNavigationState` が行い、バッジ・バー・VoiceOver の文言は同じ状態から作る。読み込み中・空・取得失敗・接続判定中は対応待ちバーを出さず、到達不可では最後に得たバッジ件数を残してオフライン表示へ置き換える。
5. 詳細・compose への push 中は `.toolbar(.hidden, for: .tabBar)` でタブを隠し、対応待ち表示も隠す。タブの選択 Binding が同じ値で呼ばれれば、AppRoot が一覧タブのルート復帰と先頭スクロール、設定タブのルート復帰を行う。
6. 対応待ちバーの表示切替では、`TabView` とタブ内の画面を同じ構造で保持する。画面本体を `if accessoryEnabled` で切り替えると一覧の `.task` が再開し、取得開始の `.loading` でバーが消え、画面の再生成と再取得が循環する。バーの表示だけを切り替え、一覧の購読・入力・ナビゲーションの状態を維持する。

## 根拠と確認範囲

- 手元の iOS Simulator SDK 26.2 で `tabViewBottomAccessory`、`tabBarMinimizeBehavior`、`Tab(role: .search)` が利用でき、iOS 18.0 Simulator SDK 向けの標準 `TabView` は型検査できた。PhloxMobile と埋め込みの PhloxWidget を含む generic Simulator ビルドも成功した。
- UIKit の `UITabBarControllerDelegate` は、すでに選択中の画面が選び直された場合も `didSelect` を呼ぶと Apple が記載している。ただし SwiftUI `TabView` がその操作で selection Binding の setter を呼ぶ保証は、確認した公開 SwiftUI 文書にはない。XCUITest と操作の合成を使っていないため、同じタブの押し直しからルート復帰・先頭スクロールへ至る実操作は未確認である。
- iOS 26 の縮小表示はスクロール開始時に OS が行う。描画テストは通常の静止描画であり、スクロールを合成しないため、縮小状態を作れるかは画像で確認できない。
- それ以外の配置・文字・余白は、iOS 26 / iOS 18 の描画画像と `Shell`・`Shell18`・`ShellOffline` の見本を見比べて記録する（作業記録 0023）。
- 決定 6 の実装では、`DSPlatformTabView` が iOS 26.1 以降は `tabViewBottomAccessory(isEnabled:)` を常に付けて表示の有無だけを渡し、iOS 26.0 は同じ modifier の中身だけを条件で切り替える。`DSPlatformTabContent` は `safeAreaInset` を常に付け、中身だけを切り替える。`TabAccessoryIdentityTests`（`ios/PhloxMobileSnapshotTests/`）が、バーの表示切替を繰り返しても一覧側の `.task` が再開せず入力中の状態が残ることを、標準タブ経由と `safeAreaInset` 経由の 2 通りで検査する。検証レビュー記録（`release/verification-reviews.json`、2026-10-26）時点で、iOS 18 と iOS 26.0 での実行、iOS 26.0 でバー非表示時に空のアクセサリ枠が残らないこと、実機での確認は未確認である。

## 結果

- ADR 0006 の「独自タブバーを使う」決定を superseded にした。独自タブ行と選択だけを担っていた `AppShellViewModel` を削除した。
- SwiftUI 公開 API が再タップを保証しない点は未確定のまま残す。Binding setter が実際に呼ばれない OS では AC-3-8 の再選択動作は発火しない。実操作で再現性が確かめられなければ、その選択通知だけを補う設計判断が必要になる。
