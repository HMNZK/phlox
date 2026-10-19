# Cursor直接ベクター描画の比較

## 目的と採否

原Cursor資産のpath・gradient・色・clipをCore Graphicsで直接描く、製品未適用の検証候補。原SVGのSHA256は `7dc00bc09f225fcda46cbc9c6b669c69c025a231877d6c17baa6a003f04f02b2`。白い矩形のluminance maskは、同じ矩形境界で隔離した透明グループを切り抜く。元SVGや共有macOS資産は変更しない。

最初はiOS 18 / iPhone 14 Plus / 16pt / 2x / light / icon-only。原本は共有 `AgentBrandIcon(kind: .cursor)` の実資産を利用し、候補と同じUIWindow、safe area、背景、renderer条件で順番に描く。RGBAの全画素が一致し、候補描画区間の `CGGStackRestore` が0件である場合だけ次へ進む。一方でも不合格なら棄却し、閾値を緩めない。警告は未加工ログのbegin/end marker間で別途集計する。

最小条件通過後のみ、iOS 18/26 × 15/16/26pt × 1/2/3x × light/darkへ広げる。続いてiOSラッパーの外周strokeを含む同条件比較を行う。診断suiteのpassは画素一致のみを意味し、警告0の証明とは区別する。

## 実行契約

実験時は新規 `CursorVectorProbeTests.swift` を `PhloxMobileSnapshotTests` に含めた。`TEST_RUNNER_PHLOX_CURSOR_VECTOR_PROBE=1`、絶対パスの `TEST_RUNNER_PHLOX_CURSOR_VECTOR_OUTPUT` を指定する。既定は最小条件、通過後に `TEST_RUNNER_PHLOX_CURSOR_VECTOR_MATRIX=1` でmatrix、さらに `TEST_RUNNER_PHLOX_CURSOR_VECTOR_WRAPPER=1` で外周stroke比較を選べる。通常のsnapshot suiteとは独立し、`-only-testing:PhloxMobileSnapshotTests/CursorVectorProbeTests` を指定する。棄却後のsourceは下記archiveへ保全し、通常test targetから外した。

親担当のsource freeze / simulator実行許可後に、`~/.agents/scripts/compact-test --full` 経由で標準 `PhloxMobileSnapshots` schemeを使う。出力は `.verification/ios-redesign-stage8b/remaining/cursor-probe/` 内へ保存し、親のビルド成果物と起動バイナリの一致を確認する。XCUITestは使わない。

## 状態

2026-10-18、実行担当 `ios_ac_composer` がcompact-test経由で最小条件を実走した。iOS 18.3.1 / 16pt / 2x / light / icon-onlyで、Swift Testingの実行は1 test / 1 suite、画素完全一致のassertionにより失敗（exit 65）。原本と候補で26画素が異なり、最大channel差は1。候補を棄却し、matrix・iOS 26・外周stroke比較は実施していない。製品原本と採用条件は変更しない。

未加工ログのbegin/end marker間で、原本の `CGGStackRestore` は1件、DirectVector候補は0件。PNGは2枚、`pixel-results.json` は1件を保存した。警告が消えても画素差0を満たさないため、修正成功とは扱わない。実行ログには `multiple matching destinations` 警告もある。

実行担当が記録した最終build-for-testing成果物SHA256は `eee151acde006c1e61b36c1b6486ea9555354b953645681391c10b0639812d67`。短時間の実行中にlsofから実ロードパス・SHAを取得できていないため、実ロードバイナリの一致は未確認。この制約を成果物のhash確認と混同しない。

一次資料は `.verification/ios-redesign-stage8b/` 内の以下にある。

- ログ: `logs/remaining-cursor-vector-ios18.log`
- xcresult: `result-bundles/remaining-cursor-vector-ios18.xcresult`
- PNG・数値: `remaining/cursor-probe/ios18-minimal/`
- 実験source: `remaining/cursor-probe/source-archive/CursorVectorProbeTests.swift`（SHA256 `5b8bb13a8147c2cc1c250f30a537dc76d908c1746637add44a4ffb7341b71d16`）

このsourceは今回だけ追加した未追跡の実験であり、既存の製品テストではない。SHAが一致するarchiveを作成してから元ファイルをゴミ箱へ移し、失敗結果はそのまま残す。通常targetの製品テストを削除・スキップ・期待値変更したものではない。実験除去後の最終ビルド・正式検証は親担当の別ゲートで行う。
