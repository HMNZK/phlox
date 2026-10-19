# Errors カタログの残件回帰検査

## 目的・成功条件（実装前に記録）

2026-10-18、`ios_error_regression` が担当する。製品ソースと既存テストは編集せず、`RemainingErrorCatalogTests.swift` のみ追加する。32コードの全文照合は `.verification/ios-redesign-stage8b/remaining-error-catalog-complete.md` を前提に、専用検査がなかった失敗経路を検査する。

- D3: API の承認取得を成功→失敗→成功に切り替え、公開VM操作で取得する。失敗時は以前の承認を消し、押せる承認カードを残さず、原因・次の操作・技術詳細を表示状態へ渡す。回復後はエラーを消す。PhloxError とそれ以外の失敗の両分岐を対象にする。
- F8: 会話取得404とセッション存在照会失敗を組み合わせ、削除済みと断定しない分岐と、その後の存在確認成功を検査する。
- F3: 一覧の取得失敗、新規作成失敗が429を無彩色の presentation として渡し、入力を保つことを検査する。最終描画色はこの検査の範囲外。
- D6: 子孫付き削除の失敗から再試行成功までを実VMで検査し、失敗時に完了通知せず、再試行成功後に失敗presentationを消す。

## 公開APIで確認できない範囲

C1のタイムアウト判定は `Features.PairingConnectGate` にあるが、本番の接続先・3確認項目・再試行/閉じるを生成する `AppRoot.makeConnectFailure` はアプリターゲットのprivateメソッド。packageテストから本番presentationへ結合する公開経路はない。文字列をテスト側で再生成した比較では証明しない。

D6の等幅技術欄は `DeleteConfirmationView.failureMessage` 内のprivateなAttributedStringから標準Alertへ渡す。属性・ボタンroleを取り出す公開APIはなく、VMテストでOSアラートの属性・組版を確認したとは扱わない。private APIやSwiftUI内部構造への依存は追加しない。

F3の3画面の色分岐はprivateなView builderにある。VMの `isNeutral` 伝播と、最終画面の描画色は別の検証として扱う。ソース正規表現を最終色の代用にしない。

## 品質設定と実行状態

`ios/Packages/PhloxKit/Package.swift` の FeaturesTests（Swift 6）、`ios/project.yml`、`ios/scripts/lint-raw-values.sh` を確認。新しい依存・品質ツールは追加しない。SwiftPMの実行は親のsource freeze後の検証に委ね、独自scratchを作らない。XCUITestは実行しない。

追加した6テストは、初回の統合検証でコンパイル失敗したため未実行。`:10` の省略形 `.notFound` が存在型 `Error` から解決できなかったため、`PhloxError.notFound` と型を明示した。期待値・検査内容は変更していない。修正後の `swiftc -frontend -parse` と `git diff --check` は exit 0。テストファイルのSHA256は `345b2ea315f905cc4d8afc95b40c7fbe59105eb755a978749d1c30d7298672c7`。再コンパイルとテスト本体の実行は統合検証担当の再実行待ちで、構文確認だけをテスト成功とは扱わない。

この担当は検証用build/scratch/ログ・常駐プロセスを作成・起動していないため、片付け対象のPIDはない。新規作成失敗の検査は独立UserDefaults suiteを読み取り、設定の保存経路へ進まない。
