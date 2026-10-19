---
status: active
---

# 残る実行時検証の独立ハーネス

## 先行契約

- 本物の `UsageRingRow` が開くpopoverの最大文字サイズを検査する。自動suiteでは公開UIKitの `UIScrollView.accessibilityScroll(.down)` の能力を記録する。外部CUA専用suiteでは実offsetが増加して内容の末尾へ到達し、先頭へ復帰することを必須とする。`setContentOffset` は使わず、公開アクセシビリティ操作をタッチgestureの検証とは呼ばない。
- 本物の `DeleteConfirmationView` と公開ViewModelをhostし、実 `UIAlertController` のnative最大文字サイズ、2つのactionの役割、実buttonのframeを公開UIKit/AXから調べる。AC-10-5どおり実行が上・キャンセルが下の縦積みで、枠が重ならず最低44ptの高さを確保することを必須とする。私製alertやボタンを描かない。
- 公開操作拒否は能力記録にunsupportedと明示する。受理された公開操作でoffsetが動かない・外部操作で末尾/先頭へ届かない・標準buttonのframeを公開情報から取れない場合は失敗と理由を記録する。成功条件を弱めるfallbackは設けない。
- PNGと測定JSONを `.verification/ios-redesign-stage8b/remaining/` 配下へ保存する。`PHLOX_REMAINING_HOLD=1` ならnonce・scene・pid・udidとackの保存先をready JSONで親へ通知し、親CUAの実画面確認を待つ。要求したholdの期限内に正しい確認が届かなければ失敗する。

## 所有と検証

新しい `RemainingAcceptanceTests.swift` と本記録だけを変更する。既存の撮影テスト・製品・他担当ファイルは変更しない。`ios/project.yml` はsnapshot targetの全テストフォルダをsourceとして扱うため、依存やtargetの追加は不要。`ios/Makefile` のsnapshot入口と既存schemeを使い、ビルド・実行・Simulator操作は親のGOまで行わない。XCUITest・private API・OS設定変更は使用しない。

native hostには自身のUIWindowとcontrollerのtraitOverrideを使う。読み取り専用環境値へ書き込まず、表示・native presentationの解消・非表示が終わってからrootを外す。通常アプリ・共有環境の設定は変更しない。

## 実行用の取り決め

対象は `PhloxMobileSnapshotTests/RemainingAcceptanceTests`。2テストを直列で実行し、既存fullの描画ソースへ変更を混ぜない。`PHLOX_REMAINING_OUTPUT` は絶対パスの出力先を任意指定でき、未指定時は上記の専用領域を使う。実行ごとのディレクトリはscene・OS・UUIDを含み、実測JSON/PNGを上書きしない。

`PHLOX_REMAINING_HOLD=1` の場合、スクロール末尾 `bottom`・先頭復帰 `top`・標準alert `native-alert` の各撮影時に `<step>-ready.json` が出る。親はその時点の実画面を確認し、readyの `ackFile` へ下記JSONを原子的に保存する。確認中に画面を操作しない。nonce/scene/step/pid/udidはreadyの実値、capturedAtはfresh画面確認時のUnix秒を使う。待機は各60秒で、期限切れ・別実行の応答・確認NGは失敗する。

```json
{"nonce":"ready値","scene":"ready値","step":"ready値","pid":123,"udid":"ready値","phase":"reviewed","confirmed":true,"capturedAt":1792000000.0}
```

自動2テストにはskipや環境変数による未実行分岐を設けない。別interactive suiteは明示実行用環境変数をrequireし、未設定なら失敗する。hold未要求の実行は公開UIKit/AX検査と実画面PNG保存までで、外部CUAの目視確認済みとは報告しない。実装担当はテスト・ビルド・Simulatorを未実行。

## AC-2-8の確定差の修正契約

`.verification/ios-redesign-stage8b/remaining-dynamic-type-complete.md` の実caller監査に従い、承認カードの展開差分を横スクロールの全文表示へ変更する。行数分類・行番号・色・等幅書体・親の縦スクロール/自然高は維持し、コードは折り返さない。長い1行が表示幅より広く保持され、短い行と同じ1行の高さになることを実Viewの回帰検査で確認する。

コマンド出力の「さらに表示」「セクションをコピー」はラベル内の最小44ptを確保し、大きな文字では操作を縦へ並べる。通常の横並び、出力とコピーの原文、展開行数の契約は維持する。コピーだけの実footerの高さを測る回帰検査を追加する。

ターン使用量はアクセシビリティ用文字サイズから金額と割合を別行に分け、全文を折り返す。通常の金額書式・横1行・右寄せ・等幅書体は維持し、欠けた値を補わない。表示文字列の回帰検査で通常と拡大時の値の保持・改行・金額の優先を確認する。

追加所有は `ReplyApprovalCard.swift`、`SessionDetailCommandOutputView.swift`、`SessionDetailView.swift`、`SessionDetailTranscriptPresentation.swift` と関連FeaturesTestsのみ。FileChangeCardと他担当のテストは変更しない。`swift-ui` のレイアウト/アクセシビリティ資料と `ui-ux-design` の44pt・全文拡大の原則を参照した。ビルド・実行は親のGO待ち。

実装は、差分内容を実使用する `ReplyApprovalDiffContent` として切り出し、自然幅の行全体を横スクロールへ入れた。水平スクロール自体も内容の自然高を使う。コマンド出力の操作はAXサイズで縦配置、通常は従来の横配置とし、各ラベル内部に44pt最小幅・高さを確保した。使用量の拡大表示は純粋な書式関数で金額と割合を改行し、表示側の行数制限を解除した。

`ChatOutputStylingTests` に標準/AX1/AX5の実footerの44ptと差分の全文自然幅・非折返し・スクロールの自然高の検査を追加した。`SessionDetailTranscriptPresentationTests` に拡大時の金額優先・割合・単独値・未取得値の検査を追加した。既存の分類閾値・期待値は変更していない。実装担当の確認は `git diff --check` の指摘なしまでで、追加テストと描画・ビルドは未実行。

## PhloxKit全件の実走結果

親GO後、iOS標準入口と前回正式コマンドに従い `compact-test --full` 経由でPhloxKitの全 `swift test` を実行した。最終runはXCTest398件とSwift Testing662件（108スイート）、合計1060件成功、exit 0。警告・コンパイルエラー0件。`make -C ios lint` も同ラッパー経由でexit 0、警告0件。PhloxKitと共有AgentDomain/DesignSystemの468ファイルは実行前後でSHA manifestが一致した。

最終記録は `.verification/ios-redesign-stage8b/remaining/unit-attempt5/`、現在の集計は `unit-verification-summary.json`。追加したAC-2-8の3検査と、新エラーカタログ6検査の成功もログで確認した。新 `RemainingAcceptanceTests` はiOSのnativeテストターゲットであり、このSwiftPM実走には含まない。CUA/native UIKit・Simulator/Xcodeの検証は別途親が実施する。

途中の失敗は省略せず保持した。初回はscratch移動に伴うPCHの旧絶対パス不一致でcompile失敗し、今回所有のModuleCacheだけをTrashへ移して再生成した。次は別担当のエラーカタログテストの型未確定でcompile失敗。型修正後は既存の遅延構築ソース検査が1件失敗し、閉本文がeager構築される回帰を担当者が根本修正した。その修正の `Animatable` 隔離要件によるcompile失敗も担当者が既存方式へ適合させた。製品/テストを検証側で書き換えず、各失敗runのログ・source manifest・exitを `unit-initial-failure/`、`unit-compile-failure2/`、`unit-runtime-failure3/`、`unit-compile-failure4/` に保全して再検証した。
# iOS18 初回native検査の失敗と修正契約

初回 `remaining-native-remaining-ios18.log` は公開 `accessibilityScroll(.down)` が false・実offset 0、標準alertの2ボタンが同じY=515、両終了処理がappearanceTimeoutで失敗した。ログ・JSONは `.verification/ios-redesign-stage8b/remaining/native-ios18/` とstage8b/logsに保持する。有限viewport731/content1530.67/enabled=trueのため、公開AXメソッド未受理から製品のスクロール不能とは判断しない。

新規テストの「公開AXメソッド対応を必須とする」仮定を訂正する。自動suiteは実popoverの構造とAPI能力を測定し、未対応を明記する。末尾・先頭への実移動は別interactive suiteで外部CUA操作後の本物UIScrollViewのoffsetを必須検査する。API falseからの自動fallback、直接offset設定、既存製品テストの削除や期待緩和は行わない。

親が専用iOS18 SimulatorだけOS文字サイズをAX5へ設定・再読した。alertはglobal/controller/viewのcategory、実UILabel font point size、配置PNGをアサーション前に保存し、44pt・実行が上/キャンセルが下の期待は維持する。表示用containerは子の正式containmentとpaired appearanceを管理し、window非表示でviewDidDisappearが必ず来るという誤仮定を除く。実runでappearance警告0を確認するまでは未検証。製品変更なし、build/SIM実走は親GO待ち。


## 修正後の実行指定と外部スクロール応答

### r6/r6bの末尾未到達を保持して先頭まで検査する

親の実CUAによる末尾要素スクロールでは実offset800.667、従来の厳密終端式812.667との差12ptで失敗した。最終API95%は親画像で可視だったが、物理終端到達とは区別する。titlebar focus後の座標wheel/dragは見た目に変化せず、入力の届き方は未特定。末尾padding12ptと差が一致するが、座標/余白の追加実測前に原因とは断定しない。

末尾の移動・厳密終端判定を非致命の `#expect` にする。失敗はテスト失敗として残し、同runで先頭への実操作と従来の厳密判定を続ける。閾値・終端式・製品は変更しない。各metricへcontentInset/adjustedContentInset/safeAreaInsetsと公開UILabel/AX由来の実label座標を追加し、取得不能は明記する。label末尾候補は取得した要素の最下端であり、取得不能なSwiftUI全文の末尾を証明するものではない。追加修正はbuild/run未実行。

自動2本は `PhloxMobileSnapshotTests/RemainingAcceptanceTests`。`usagePopoverHasFiniteViewportAndRecordsPublicAXCapability` の成功は構造と能力測定の成功であり、scroll完了ではない。標準alertは `nativeDeleteAlertStacksExecutionAboveCancelAtAX5`。外部操作は `PhloxMobileSnapshotTests/RemainingInteractiveAcceptanceTests/usagePopoverExternalScrollReachesBottomAndReturnsToTop` を単独選択し、`PHLOX_REMAINING_INTERACTIVE=1` を必須にする。`PHLOX_REMAINING_OUTPUT` は既存の絶対出力先指定、`PHLOX_REMAINING_HOLD=1` はPNGの外部画面確認を追加する独立設定。

外部操作suiteは `scrollToBottom-ready.json` → `scrollToTop-ready.json` の順。readyのphaseは `awaitingScroll`、action/stepは `scrollToBottom` または `scrollToTop`。nonce/scene/pid/udid/requestedAt/ackFile/screenshotFileとwindowポイント単位のviewportRectInWindow、previousOffsetY/targetOffsetYを通知する。親は実CUAで要求の端まで操作し、readyのackFileへ下記を保存する。各待機60秒、ack後400msで実offsetを保存・必須検査する。自己申告だけでは通らず、直接offset設定もない。

```json
{"nonce":"ready値","scene":"ready値","step":"scrollToBottom","action":"scrollToBottom","pid":123,"udid":"ready値","phase":"acted","confirmed":true,"capturedAt":1792000000.0}
```

先頭要求ではaction/stepを `scrollToTop` にする。HOLD有効なら実端到達後に既存のbottom/topの `awaitingCUA` / `reviewed` protocolも別途行う。表示内容を操作してよいのは `awaitingScroll` の間。初回失敗のcanonical log/JSONパスとSHAは `remaining/native-initial-failure18/manifest.json` に記録した。修正後build/runは未実行、appearance警告0も未確認。
