---
status: completed
last-verified: 2026-10-05
---

# Markdown スクロール性能

## 判断

- r3（PM判断）: 表の選択入口の共有は効果を確認できず撤去する。表区間の最大50.69→44.07 / 50.04ms、16.7ms超39→33 / 22件でばらつきがあり、約180行の字体・選択の再現はKISSに反する。
- 表の選択の本番コードと付随する既存テストは dev（257be72）と同じ状態へ戻す。ブロックとリンクのホバーを行へ移した修正、4種類の回帰検査、画素比較、表区間を分離する計測は残す。
- 今回は本書だけへ記録し、完了済み0039〜0041とADRは変更しない。
- 実際のファイルタブを画面外800×600ptのウィンドウへ載せ、64pt刻みの往復を計測する。実際と同じホバー更新クロージャをコードから呼ぶ。画像の符号化・GPU合成・実入力は計測範囲外。画面の操作・前面表示・稼働中アプリの終了は行わない。
- Release・明示指定時だけ性能を測り、全6条件のp95 ≤ 16.7msを検査する。通常実行と文書がない場合は既存の条件どおり性能測定だけスキップする。
- r3の最終前後比較は、表の独自選択を撤去した状態で再測定する。修正前はdevの表示処理へ計測用の入口だけを加え、ホバー更新の親再評価を含める。撤去後は同じハーネスと文書で2回測る。
- UIのbuild-for-testingは今回の明示指定 `-derivedDataPath /tmp/PhloxUIBatch` を使う（worktree内制約の指定例外）。XCUITestは実行しない。

## 原因と未解決の課題

- ブロックのホバー更新で親の文書全体とMarkdown本文が再評価される。行の状態へ移し、本文を更新クロージャの外で構築する。リンクの状態も行と行き先表示からだけ読み、親の再評価を避ける。ただし、実際のホイール操作で止まったポインタの下の行のホバーが発火するかは未確認（合成イベントではSwiftUIのホバーが発火せず再現できない）。
- 再入場で文字選択部品の生成費用が残る。過去の診断では大きい表で49〜58部品を生成して33〜43msだった。選択部品を独自実装で再現する変更は採用しない。
- 最終状態でも表区間の単発遅延が残る（最大37.93 / 42.03ms）。表区間のp95は修正後3回とも16.7msを超える（16.97 / 18.84 / 18.37ms）。内訳は未特定で、未解決の課題とする。ソースの最初の移動にも66.93 / 86.64msが残り、ソース処理は変更していない。
- 初期の毎フレーム画像合成と全配列の行検索は計測負荷を含むため、最終比較の基準に使わない。PNGの符号化結果ではなく画素を比較する。

## 修正前後の数値

Apple M4 Pro（Mac16,8）、macOS 26.6.2、Release。画面外800×600pt・64pt刻み・往復・ブロックホバーあり。表の本番コードは3回ともdevと同じ。修正前はdevの表示処理へ計測用入口だけを加え、撤去後は最終ソースで2回測定した。この比較は残したホバー修正を含み、表の選択入口の撤去だけの効果とは扱わない。時間はms、各欄は **p50 / p95 / 最大**、超過は16.7ms超の件数。

| 文書・表示 | フレーム | 修正前（dev） | 撤去後1回目 | 撤去後2回目 | 超過 前 / 後1 / 後2 |
|---|---:|---|---|---|---:|
| DESIGN.md・レンダリング | 1346 | 12.95 / 34.12 / 67.06 | 2.75 / 15.50 / 37.93 | 3.58 / 16.95 / 42.03 | 622 / 49 / 70 |
| DESIGN.md・ソース | 1306 | 1.92 / 4.67 / 68.14 | 1.78 / 4.56 / 66.93 | 1.10 / 2.70 / 86.64 | 1 / 1 / 1 |
| 表なし・レンダリング | 1282 | 15.71 / 29.76 / 59.05 | 2.43 / 10.25 / 39.06 | 2.72 / 10.84 / 29.79 | 607 / 16 / 22 |
| 表なし・ソース | 1302 | 1.11 / 4.58 / 54.70 | 1.76 / 4.74 / 12.18 | 1.21 / 2.75 / 6.43 | 2 / 0 / 0 |
| 小文書・レンダリング | 30 | 16.16 / 25.07 / 25.92 | 2.19 / 6.63 / 8.08 | 2.18 / 4.61 / 4.61 | 14 / 0 / 0 |
| 小文書・ソース | 32 | 0.58 / 1.19 / 3.50 | 0.52 / 1.35 / 4.98 | 0.33 / 0.88 / 3.07 | 0 / 0 / 0 |

| DESIGN.mdの表区間 | フレーム | p50 / p95 / 最大 | 超過 | 新規文字部品 最大 |
|---|---:|---|---:|---:|
| 修正前（dev） | 723 | 18.25 / 37.19 / 67.06 | 374 | 57 |
| 撤去後1回目 | 723 | 3.08 / 16.97 / 37.93 | 37 | 57 |
| 撤去後2回目 | 723 | 3.81 / 18.84 / 42.03 | 54 | 57 |

DESIGN.mdの親body評価は644→0 / 0回。ホバーの親再評価は抑えられているが、撤去後2回目の全体p95 16.95msは基準16.7msを超え、**1テスト・1失敗**。1回目は6条件が基準内（1テスト・失敗0）だった。2回とも成功したとは扱わず、性能基準を安定して満たすことは確認できていない。2回目は全体の超過70件中54件が表の区間にある。内訳は未特定。期待値・計測手順は変更していない。

修正前はレンダリング3条件のp95が基準を超過し、1テスト・3失敗（34.12 / 29.76 / 25.07ms）。ソースの前後差は改善の効果と扱わない。根拠は `.build/scroll-performance/r3-before.json`・`r3-after.json`・`r3-after-repeat.json` と各 `*-slow.json`・ログ。

文書: CapweaveのDESIGN.md、102,576バイト・2,044行（末尾改行を空行として数えない）、SHA-256 `fe8ede176892ae73d0fce8068529370d4d8f0a7172d264dc8fe58be6a35a907a`。r3で端末条件・文書のバイト数・行数・ハッシュを再確認した。`PHLOX_SCROLL_FIXTURE` で絶対パスを指定、既定は `/tmp/capweave-DESIGN.md`。文書は同梱しない。

## 対応

| 作業記録の項目 | 状況 | 設計 |
|---|---|---|
| 表の入場時の遅延 | 判断で変更。共有選択入口と付随テストを撤去し、devと同じ標準選択へ戻す。区間計測は残す | NFR-9・§3.8 |
| PNG比較の不安定さ | 画素バッファで比較する仕組みを残す | NFR-9 |
| 決定論的な回帰防止 | 親の評価回数・本文構築・リンク背景・リンクによる親評価の4種類を残す | NFR-9 |
| リンクの背景抑止 | 行背景が出ない画素比較を残す | §3.8 |
| リンクでの親再評価 | 状態を行と行き先表示へ移した修正を残す | NFR-9・§3.8 |
| 資料・測定条件 | 選択入口の記述をarchitectureから削除。NFR-9の全体・表区間計測は維持 | NFR-9 |

## 記録

- r3: 実装前にPMの撤去判断と再検証範囲を本書へ反映。r2の共有選択入口を採用する記述と、それに付随する写真・テストの現行状態の主張を削除した。
- r1〜r2の試行ログと画像は `.build/scroll-performance/` に残す。過去の検証結果は今回の成功として数えない。
- r3: 表のテーマ・表幅テスト・撮影テスト・ブロック操作UIテストの4ファイルがdevとバイト一致。表の独自選択の2テストと選択監視の専用分岐を撤去した。残る回帰は3テストで4種類の検査を実行し、10回・成功30件・失敗0（各回で既存の条件付き性能測定1件スキップ）。
- r3: 撤去後とdevを新しく画面外撮影し、各125枚・2テスト成功。直後に `cp -R` で `.build/scroll-performance/r3-snapshots-final/`・`r3-snapshots-dev/` へ保存。表を含むMarkdown14状態が画素一致（`r3-snapshot-comparison.json`）。見本との目視比較ではホバー面・リンク表示・表の配置を確認。見本と撮影文書の本文は既存の差があり、今回は本文を変更しない。未採用の4k・4lは既存の撮影対象外。

## 検証

以下は `~/.agents/scripts/compact-test --full <ラベル> …` 経由。ログは `.build/scroll-performance/r3-*.log` に保存した。

| コマンド | 結果 |
|---|---|
| `SWIFT_TEST_OUTPUT=full bash macos/scripts/run-swift-tests.sh` | 最終ソースで既定6パッケージと実git別パス成功。Swift Testing報告4,078件、XCTest 7件、失敗0。既存の条件付きスキップはSwift Testing 15件＋XCTest性能測定1件。`r3-default-final.log` |
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter MarkdownScrollPerformanceTests` | 4件（回帰3件成功、既存の条件付き性能測定1件スキップ）、失敗0。最終ビルドで `--skip-build` を付けて10回、回帰成功30件・失敗0。`r3-final-repeat-1.log`〜`r3-final-repeat-10.log` |
| `PHLOX_SCROLL_PERFORMANCE=1 PHLOX_SCROLL_LABEL=r3-before swift test --package-path macos/Packages/DashboardFeature -c release --no-parallel --filter MarkdownScrollPerformanceTests.testScrollFrames` | 修正前比較は1件・3失敗。レンダリング3条件のp95超過を検出。比較後に最終ソースへ復帰し、バイト一致を確認 |
| `PHLOX_SCROLL_PERFORMANCE=1 PHLOX_SCROLL_LABEL=r3-after swift test --package-path macos/Packages/DashboardFeature -c release --no-parallel --filter MarkdownScrollPerformanceTests.testScrollFrames` | 撤去後1回目は1件・失敗0、6条件の全体p95が基準内 |
| 上記に `--skip-build`、`PHLOX_SCROLL_LABEL=r3-after-repeat` を指定 | 撤去後2回目は1件・1失敗。DESIGN.mdレンダリングの全体p95 16.95msが基準16.7msを超過 |
| `PHLOX_DESIGN_SNAPSHOTS=1 PHLOX_DESIGN_SNAPSHOT_SCOPE=files swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter DesignSnapshotRenderTests` | devと撤去後の各2テスト成功・125枚。撤去後は `--skip-build`。直後に専用フォルダへコピー |
| `python3 .build/scroll-performance/r3-compare-snapshots.py` | 表を含むMarkdown14状態がdevと画素一致。不一致0。`r3-pixel-comparison.log` |
| `macos` 内で `/opt/homebrew/bin/xcodegen generate`、`xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath <worktree>/.build/DD build` | 生成成功、`BUILD SUCCEEDED`。`r3-xcodegen.log`・`r3-debug-build.log` |
| `macos` 内で `xcodebuild -project Phlox.xcodeproj -scheme PhloxUITests -configuration Debug -derivedDataPath /tmp/PhloxUIBatch build-for-testing` | `TEST BUILD SUCCEEDED`。`r3-ui-build-for-testing.log`。UIテストは未実行 |

既定の報告件数: AgentDomain 589、DesignSystem 193、MessageStore 42、SessionFeature 1,217、DashboardFeature 本体1,995＋実git 26＋XCTest 4（性能測定1件スキップ）、SimulatorBridgeKit 16＋XCTest 3。触ったSessionFeature・DashboardFeatureの全数も含む。

既定テストの既存警告はactor隔離・非推奨アクセシビリティAPI・不要なtry・未使用結果・ViewBuilderの明示returnなど（位置付き原文595行）。変更した `MarkdownBlockEditor.swift`・`MarkdownScrollPerformanceTests.swift` の警告は0行。Debugビルドには `DashboardView.swift:606` のViewBuilder警告とAppIntents依存なしのメタデータ抽出スキップ2行がある。ad-hoc署名によるhardened runtime無効・登録スクリプトの毎回実行は既存のnote。原文は上記ログに保存した。
UIのbuild-for-testingには `PTYKit/Posix.swift:182` の `init(cString:)` 非推奨、同じViewBuilder警告、AppIntentsメタデータ抽出スキップ3行がある。今回変更したSwiftの警告はない。上記と同じ既存noteもあり、原文は `r3-ui-build-for-testing.log` に保存した。

最終差分のファイルは以下の5件。既存の未コミット変更へ重ね、commit・push・mergeは行っていない。

- `macos/Packages/DashboardFeature/Sources/DashboardFeature/Tabs/MarkdownBlockEditor.swift`
- `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/MarkdownScrollPerformanceTests.swift`（追加ファイルを修正）
- `macos/docs/specs/file-explorer-and-markdown-editing.md`（既存のNFR-9の計測記述を維持。選択入口の記述がないことを確認）
- `macos/docs/architecture/file-explorer-and-markdown-editing.md`
- 本書（追加ファイルを修正）

表の選択関連でdevへ戻した4ファイルは、`SessionFeature/Sources/SessionFeature/FileMarkdownTheme.swift`・`DashboardFeature/Tests/DashboardFeatureTests/RichMarkdownViewTests.swift`・`DesignSnapshotRenderTests.swift`・`macos/UITests/MarkdownBlockInteractionTests.swift`。最終差分はない。

記録: 共有選択入口を撤去し、ホバー修正・4種類の回帰検査・画素比較・計測を残した。既定全数・回帰10回・画素比較・Debugビルド・UIテスト用ビルドは成功した。UI実行用は `/tmp/PhloxUIBatch/Build/Products/PhloxUITests_macosx26.2-arm64.xctestrun`。Release2回目の基準超過と単発遅延は未解決であり、本書は `in_progress` のままとする。期待値の緩和や成功するまでの再測定は行っていない。

専用lint・独立した静的解析は未設定。実入力・GPU合成・実機の体感は未検証。

PMが実入力で実行する指定:

```text
-only-testing:PhloxUITests/MarkdownBlockInteractionTests/testSourceHighlightingKeepsUndoAndSavedBytes
-only-testing:PhloxUITests/MarkdownBlockInteractionTests/testBlockEditingSaveAndModes
-only-testing:PhloxUITests/MarkdownBlockInteractionTests/testReferenceLinkOpensFileWithoutEditing
```

## 最終状態

- ホバーによる親の再評価をなくす修正を採用（DESIGN.md レンダリング表示 p95 34.12→15.50 / 16.95ms、超過 622→49 / 70）。PM レビューの指摘でリンクのホバー用クロージャを本番とテストで共有した。
- PM 検証（2026-10-05）: `run-swift-tests.sh` Swift Testing 4,078件＋XCTest 成功・失敗0、UI テスト4件成功（MarkdownBlockInteractionTests 3件・FileTreeInteractionTests 1件）。
- 未解決: NFR-9 は安定して満たしていない（表区間の単発遅延・p95 超過、上記）。実入力のホイール操作でのホバー発火と体感は未確認。
