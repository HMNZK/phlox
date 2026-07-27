---
status: accepted
last-verified: 2026-07-27
---

# ADR 0033: セッション詳細はシステムのナビゲーションバーを使う（自前 chrome と端スワイプは両立しない）

> **このファイルの役割**: 「ナビゲーションバーを隠して自前ヘッダを描く」構成をやめ、システムのナビゲーションバーへ chrome を載せ替えた決定と、そう判断するに至った実機での観測。
> **書かないもの**: 差し替え前の経緯（→ [ADR 0032](0032-interactive-pop-gesture-on-hidden-navigation-bar.md)。本 ADR が supersede する）。

## 文脈

[ADR 0032](0032-interactive-pop-gesture-on-hidden-navigation-bar.md) は、ナビゲーションバーを隠したまま端スワイプ pop を成立させるために `interactivePopGestureRecognizer` のデリゲートを自前のものへ差し替えた。XCUITest は green で、端スワイプでは戻れるようになった。

しかし実機（iPhone 14 Plus / iOS 26.5.2）で使うと、**端スワイプで戻った後に一覧の大タイトル「Projects」が消え、上部が空白になる**。UIKit 既定のデリゲートが「バーが隠れている画面ではジェスチャを開始しない」と判断しているのは、まさにこの遷移（隠す画面 → 見せる画面）でバーの状態を正しく引き継げないからであり、差し替えはその安全弁を外していた。

対症療法を2回試し、2回とも失敗した。

1. **遷移完了時に `setNavigationBarHidden(false)` を呼ぶ**: 端スワイプだけでなく**戻るボタンでもタイトルが出なくなった**（悪化）。この時点でユニットテスト 561・シミュレータ 24・実機 8 がすべて green だったにもかかわらず、である。ここから、pop 完了の時点ではまだバーが隠れており、SwiftUI はその**後**に自分のタイミングで復帰させていること、UIKit を先回りで触るとその復帰が空振りする（＝タイトルの無いバーが残る）ことが分かった。
2. **元のデリゲートへ委譲する転送プロキシ**: UIKit の拒否が戻るだけで、端スワイプ自体が効かなくなった。

**この症状は自動テストで再現できていない**。シミュレータ（iOS 26.2）でも実機でも、`-UITesting -UIScenario=goldenPath` のモック下ではアニメーションの有無に関わらず再現しない。再現手段を持たないまま推測で当てにいく手当てを重ねるべきではない。

## 決定

**セッション詳細でナビゲーションバーを隠すのをやめ、chrome をシステムのナビゲーションバーへ載せる。**

1. `.toolbar(.hidden, for: .navigationBar)` と自前 `topBar`（ZStack の overlay）を廃止する。
2. タイトルは `.navigationTitle(displayName)` ＋ `.navigationBarTitleDisplayMode(.inline)`。
3. 戻るボタンは**システムのものを使う**。`.toolbarRole(.editor)` で戻るラベルを落とし、従来と同じ「‹」だけの見た目にする。**leading へ自前の項目を置かない**（置くと UIKit がまた端スワイプを拒否する）。
4. メニュー（モデル変更 / 名前変更 / 削除）は `ToolbarItem(placement: .topBarTrailing)` へ移す。導線とラベルは据え置き。
5. `InteractivePopGestureRestorer`（判定層＋UIKit 接続層）を削除する。端スワイプは iOS 標準のまま成立するので、細工は不要になる。

これで「バーが隠れている画面から見えている画面へ対話的に pop する」という状況自体が消える。タイトルが失われるバグのクラスごと無くなる。

## 棄却案

- **一覧側で `.toolbar(.visible, for: .navigationBar)` を明示する**: 3度目の推測による手当てになる。再現手段が無いので当たったかどうかを自分で確かめられない。原因（UIKit の安全弁を外していること）にも触れていない。
- **端スワイプを諦めて ADR 0032 ごと revert する**: 片手操作で行き止まりになるという最初の要望に反する。
- **自前の戻るボタンを leading の `ToolbarItem` として置く**: `navigationItem.leftBarButtonItem` を差し替えると UIKit は端スワイプ pop を拒否する。同じ問題に戻る。
- **`UINavigationControllerDelegate` を実装してバーの表示遷移を自分で面倒みる**: そのデリゲートは SwiftUI の `NavigationStack` が握っている。奪うとナビゲーション全体の挙動が壊れる。

## 結果

- 見た目は従来とほぼ同じ（「‹」/ セッション名 / 「•••」）。バーの配色は他画面と同じ `dsCampNavigationChrome` の chrome になり、`.ultraThinMaterial` の半透明から不透明の `surface` に変わる。
- 端スワイプ・キャンセル・再オープン・中央スワイプ無効・根の画面での安全性は、`SessionDetailBackSwipeUITests` を無改変のまま実機とシミュレータの両方で green。
- ADR 0032 の教訓「判定層のユニットテストだけを根拠に『スワイプで戻れる』と主張してはいけない」はそのまま生きる。加えて本件は **XCUITest が green でも実機の実使用で壊れることがある**ことを示した。UIKit の既定の拒否を上書きしたら、その拒否が守っていたものを自分で肩代わりできているかを疑う。
- **未検証**: タイトルが消える症状そのものを自動テストで再現できていないため、「この変更で直った」ことは実機での実使用でしか確認できない。
