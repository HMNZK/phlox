---
status: accepted
last-verified: 2026-10-18
---

# ADR 0048: 左上のホームはシステムの戻るボタンの印を家に替えて作り、端スワイプは UIKit のまま使う

> **このファイルの役割**: 再設計の「左上はホーム・端スワイプで戻れる」（ADR 0046 の 8）を、ADR 0033 の教訓に反さずに作る方法の決定と、確かめた範囲。
> **書かないもの**: 見た目（→ [specs/redesign-2026-10.md](../specs/redesign-2026-10.md) AC-8-1〜8-3）。

## 文脈

ADR 0033 は「leading に自前の項目を置くと UIKit が端スワイプの pop を拒否する」と観測し、システムの戻るボタン（`.toolbarRole(.editor)` で「‹」だけ）を使うことにした。その前の ADR 0032 は、バーを隠してジェスチャのデリゲートを差し替え、戻った後に一覧の大タイトルが消える不具合を実機で起こした。

段階 1 の最初に、アプリにホストした単体テスト（`ios/PhloxMobileSnapshotTests/NavigationBackSwipeProbeTests.swift`。XCUITest・入力の合成は使わない）で、`NavigationStack` に 1 段 push した画面の UIKit の状態を iOS 26.2 と iOS 18.3.1 のシミュレーターで調べた（2026-10-17）。

| 作り方 | ジェスチャ有効 | `gestureRecognizerShouldBegin` | 戻るボタン | pop→push 後 |
|---|---|---|---|---|
| A: システムの戻るのまま、そのナビゲーションのバーの appearance の back indicator を `house` に | はい | true | 残る（印が家） | 変わらない |
| A2: 同じことを画面の `UINavigationItem` に | はい | true | 1 回目は家、再 push で既定の「‹」に戻る（SwiftUI が消す） | 印が戻る |
| B: 戻るを隠して leading に自前のホーム | はい | 既定のデリゲートでも true | 隠れる | 変わらない |
| C: 戻るを残して leading にホームを足す | はい | true | 「‹」と家が並ぶ | 変わらない |

B が既定のままで true を返したのは ADR 0033 の観測と食い違う。今の SwiftUI は leading の項目を `leftBarButtonItems` でなく項目グループで置き、`leftItemsSupplementBackButton` を true にしているためと見られる（推測）。ただし、この調べ方は「始めてよいか」の判断を直接呼んだだけで、指で端をなぞったときに本当に戻れるか、戻った後にタイトルが出るかは確かめていない。

## 決定

1. **A を採る。** セッション一覧のタブの `NavigationStack` の `UINavigationBar` 1 本に、back indicator を SF Symbol `house` にした appearance を掛ける。戻るボタンも端スワイプも UIKit のものをそのまま使い、デリゲートを差し替えない。ラベルは `.toolbarRole(.editor)` で出さない。
2. 押したときの動きは「1 段戻る」。セッション画面と新規チャットは一覧から 1 段なので、これが一覧（ホーム）へ戻ることになる。
3. この部品は段階 1 の共通の部品に入れ、iOS 26（ガラスの丸）と iOS 18（印だけ）の描き分けは OS の戻るボタンに任せる。

## 棄却案

- **B（自前のホーム＋戻るを隠す）**: 判断は true だったが、ADR 0033 が実機で見た拒否と食い違う理由を確かめられていない。UIKit の既定から外れた形で、指の操作を確かめる手段（XCUITest）も使えない。A は UIKit の既定のままなので、0032・0033 の失敗の型に入らない。
- **A2（画面ごとの appearance）**: SwiftUI が再 push のときに消す。
- **C**: 「‹」と家が並び、見本と違う。

## 結果

- **見本との差（解消）**: サブエージェント詳細（一覧から 2 段目）では家の印が親のセッションへ戻る問題があったが、2026-10-17 にサブエージェント詳細そのものを廃止した（仕様書 15 章 U-21）。家の印の画面は一覧から 1 段だけになり、押すと一覧へ戻る。
- **未検証**: 指での端スワイプ・家の印を押したとき・戻った後の大タイトル。シミュレーターの UIKit の状態だけを確かめた。実機での確認はユーザーに頼む（段階 6 のセッション画面の作り替えの後）。
- ADR 0033 の決定 3「leading に自前の項目を置かない」はそのまま守る。0046 の 8 の「戻るの差し替え」は、見た目だけをこの ADR の方法で行う。

## 段階 6 追記（2026-10-18）

- セッション詳細も `NavigationStackHomeBackButton` のシステム戻る印を使う。`DSSessionNavigationChrome` はナビゲーションバーの内容と iOS 26／18 の背景だけを設定し、独自の leading ボタンやジェスチャの差し替えは追加しない。
- スナップショットでは左上の表示が家の印にならず、戻る矢印のまま残った。UIKit の appearance 値を確かめる既存プローブは成功している。戻る表示モードを `.minimal` にしても変化せず、原因は未特定。独自の leading ボタンは端スワイプを崩すため導入せず、この視覚差を残す。

## 段階 6 再確認（2026-10-18）

- 前項の差は `DSSessionNavigationChrome` が詳細画面ごとに `.toolbarBackground`・`.toolbarBackground(.visible)`・`.toolbarColorScheme` を適用していたことが原因だった。UIKit の appearance は家の画像を保持していたが、詳細画面の SwiftUI toolbar が表示上の戻る印を矢印に戻していた。
- これらの画面単位の指定を外し、バーの背景と配色は `NavigationStack` に適用された `DSCampNavigationChrome` に任せた。詳細の描画で iOS 26・18 とも左上が家になり、タイトル中央寄せを保つことを確認した。戻るボタン、端スワイプの delegate、leading 項目は置き換えていない。
- `NavigationBackSwipeProbeTests.homeBackIndicatorPreservesInteractivePopAcrossPopAndPush` は両 OS のスナップショット実行内で成功。これは UIKit のジェスチャ状態を読む確認であり、指での端スワイプや実機操作は未確認。

## 段階 6 最終見比べ（2026-10-18）

- 左上の家が遅れて出る原因ではなく、詳細画面の toolbar 背景・配色指定が SwiftUI の戻る印を矢印へ戻していた。画面単位の指定を外した状態で iOS 26・18 の初回描画から家を確認した。システムの戻るボタンと UIKit の端スワイプは維持する。
- 右上メニューは iOS 26 で `GlassSurfaceRole.roundButton` の丸いガラス面を使い、`ToolbarItem` の共有背景を隠して二重面を防ぐ。iOS 18 は plain の印だけにする。タイトル中央寄せのため、詳細経路の `.toolbarRole(.editor)` を外した。
- 状態の語とエージェント名を別々の色で組み立てる。Codex の `gpt-6.1-sol` は選択肢データに `medium` が無かったため、描画 fixture に「中」を足した。表示規則は変えていない。
