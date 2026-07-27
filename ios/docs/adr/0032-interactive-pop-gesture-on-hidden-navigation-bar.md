---
status: accepted
last-verified: 2026-07-27
---

# ADR 0032: ナビゲーションバーを隠した画面の端スワイプは、ガード付きデリゲートへ差し替えて復活させる

> **このファイルの役割**: セッション詳細で iOS 標準の「端から右へスワイプして戻る」が効かない問題を、UIKit のどこに手を入れて直したか、そしてなぜ有効化だけでは足りないかの決定。
> **書かないもの**: セッション詳細の画面構成そのもの（→ [architecture/overview.md](../architecture/overview.md)）。

## 文脈

セッション詳細は `.toolbar(.hidden, for: .navigationBar)` でナビゲーションバーを隠し、独自の戻るボタンを置いている。この状態では iOS 標準の端スワイプで戻れず、片手操作で行き止まりになる。

最初の実装は `UIViewControllerRepresentable` 越しに `interactivePopGestureRecognizer.isEnabled = true` を書き戻すだけだった。判定層（スタックの深さが2以上のときだけ有効化する）は純粋な関数として切り出され、fake のホストに対するユニットテストも green だった。

**それでも実機経路では1ミリも動いていなかった。** iPhone 16 シミュレータ上の XCUITest で実測したところ、端スワイプしても画面は pop しない。原因を切り分けるため `delegate = nil` を足しただけの診断ビルドを作ると、同じテストがすべて通った。

つまり **ナビゲーションバーを隠すと、UIKit 既定のデリゲート（`_UINavigationInteractiveTransition`）が `gestureRecognizerShouldBegin` で false を返し、ジェスチャの開始そのものを拒否する**。`isEnabled` は有効なのに始まらない。有効化だけでは足りない。

## 決定

1. **開始条件を明示した自前の `UIGestureRecognizerDelegate` へ差し替える**。`gestureRecognizerShouldBegin` は「ナビゲーションスタックの深さが 2 以上」かつ「遷移中でない（`transitionCoordinator == nil`）」ときだけ true を返す。
2. **同時認識は許さない**（`shouldRecognizeSimultaneouslyWith` は常に false）。この画面にはターミナル出力カードと Markdown の表という横スクロール領域があり、取り合いになる。
3. **元のデリゲートを保存し、画面を離れるときに戻す**。同じ `UINavigationController` に載る他の画面（ナビゲーションバーが見えている画面）の挙動を恒久的に変えない。
4. デリゲートは gesture recognizer から weak 参照されるので、**接続層の view controller が強参照を持つ**。
5. **判定層は UIKit 非依存のまま保つ**。UIKit への接続は `#if os(iOS)` の内側に隔離し、判定層は `UINavigationController` を知らない（macOS ホスト上の `swift test` で回せる状態を維持する）。

## 棄却案

- **`isEnabled = true` だけに留め、デリゲートには触らない**: 実測で動かないことが確定した。この方針では要望を満たせない。
- **`delegate = nil` の裸使用**: 動きはするが、UIKit 既定の安全弁（根の画面では始めない・遷移中は始めない）を同時に外す。ナビゲーションが固まる・遷移が二重に走る類の事故を招く。
- **本文へ `DragGesture` を敷いて自前で pop する**: 縦スクロール・キーボード・横スクロールと競合する。画面中央からの右スワイプでも戻ってしまい、表や出力カードの横スクロールを奪う。
- **ナビゲーションバーを隠すのをやめる**: 画面上部の情報密度を優先した既存の設計判断を覆すことになる。

## 結果

- 端スワイプで戻れる／戻った後に開き直せる／浅いスワイプはキャンセルされる／中央からのスワイプでは戻らない、が XCUITest で green。
- デリゲート差し替えで最も危ないのは「離脱時に元へ戻す処理が、対話的 pop を**キャンセル**したときに自分自身を壊す」ケース（キャンセル時は `viewWillDisappear` → `viewWillAppear` の順に呼ばれる）。キャンセル1回後・2回後の再スワイプ、根の画面での端スワイプ後の再オープン、横スクロール領域の上から始めた端スワイプ、いずれも戻れることを実測して確認した。
- **この欠陥は in-process のユニットテストでは原理的に検出できない**。fake のホストに対する「有効化されたか」の確認は、UIKit が実際にジェスチャを開始するかを何も語らない。恒久の回帰ガードは `ios/PhloxMobileUITests/SessionDetailBackSwipeUITests.swift`（XCUITest）に置いている。判定層のユニットテストだけを根拠に「スワイプで戻れる」と主張してはいけない。
