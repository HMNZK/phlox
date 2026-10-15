---
status: completed
last-verified: 2026-10-15
---

# DashboardFeature の端末フォント参照クラッシュ

## 原因と対処

SwiftTerm のクラス構造変更後、古い呼び出し側の生成物が残り、関数の呼び出し位置がずれた。製品ソースと既存テストの期待値は変更せず、依存するパッケージの生成物を再構築した。PTYKit と ADR 0212・0213 は変更していない。

単独再現は `BottomPanelTests/twoWindowsAndContentHeight`。`compact-test → run-swift-tests.sh DashboardFeature` で signal 11、終了1となった。クラッシュ報告は `/Users/ryosuke/Library/Logs/DiagnosticReports/swiftpm-testing-helper-2026-10-15-185044.ips`。

スタックの先頭は次のとおり。

```text
objc_msgSend + 32
BottomPanelTests.swift:204 の #expect のマクロ展開
BottomPanelTests.twoWindowsAndContentHeight()
Swift Testing のテスト呼び出し
```

`pointSize` の受信先を保持するレジスタ x0 は `TerminalView.fontSet.modify.resume.0` の関数アドレスであり、NSFont ではなかった。LLDB で保存済みのテスト実行ファイルを逆アセンブルすると、古い呼び出し側はクラスの関数表の `0x530` をフォント取得として呼び、その戻り値に `pointSize` を送っていた。SwiftTerm の生成物は18:45、当該テストは18:00のもので、関数表の新旧が混在していた。経緯の（3）で追加された `optionArrowKeyCodes` は保存プロパティであり、クラス構造を変更している。

新しい回帰テストの追加でテストターゲットを再コンパイルすると、製品ソースも既存テストも変更せずに、元の失敗テストが単独で成功した。さらに `swift package --package-path macos/Packages/<名前> clean` を TerminalUI・DashboardFeature・SessionFeature に各1回実行（終了0）し、関連テスト17件が成功した。これにより、フォントの寿命や Option キー処理そのものの不具合ではなく、古い生成物の混在だったことを確認した。Swift コンパイラ／SwiftPM 内部の依存追跡処理の特定・修正は本作業の範囲外。

## 変更

- `TerminalFontAccessTests.swift` を追加。フォント変更と、画面外ウィンドウへの再接続を通じて11・13・20ptの実サイズを確認するSwift Testingの1テスト。
- `architecture/terminal-editor-panels.md` に構造変更後の依存パッケージのクリーン手順とテストの役割を記録。
- 本資料に調査証拠と検証結果を記録。既存のアーキテクチャ判断を置き換えないため新ADRは不要。

## 作業中の検証

テストコマンドは `~/.agents/scripts/compact-test <ラベル> macos/scripts/run-swift-tests.sh <名前>` が入口。全ログが必要な再現・比較では `compact-test --full` と `SWIFT_TEST_OUTPUT=full` を使った。

| SWIFT_TEST_FILTER / 対象 | 結果 | 終了 |
|---|---|---:|
| `BottomPanelTests/mountAndShareAcrossWindows` / DashboardFeature | 誤った名前で0件。検証として採用せず、実際の名前で再実行 | 0 |
| `BottomPanelTests/twoWindowsAndContentHeight` / DashboardFeature、再コンパイル前 | signal 11 | 1 |
| `TerminalFontAccessTests` / DashboardFeature | 1件成功 | 0 |
| `BottomPanelTests/twoWindowsAndContentHeight` / DashboardFeature、再コンパイル後 | 1件成功、実フォント13pt | 0 |
| `BottomPanelTests TerminalFontAccessTests TerminalWordMovementTests` / DashboardFeature、clean後 | 17件成功、3スイート | 0 |

調査では、シンボル名を渡した `dwarfdump --lookup` はアドレス指定が必要なため失敗（終了1）。LLDB の一部の名前検索も該当なしで終了1だった。成功した関数名検索とアドレス指定の逆アセンブル、およびクラッシュ報告から上記の位置を確認した。リポジトリ直下の AGENTS.md は存在せず、提示された規約と `macos/docs/README.md` に従った。

## 最終検証

全件は次のコマンドで各パッケージ1回だけ実行した。DashboardFeature の本体と実Git側の分割は既存スクリプトの規則で、両方を実行している。

```sh
env -u SWIFT_TEST_FILTER -u SWIFT_TEST_SKIP PHLOX_TERMINAL_SNAPSHOT=1 SWIFT_TEST_OUTPUT=full \
  ~/.agents/scripts/compact-test --full st-crash-final \
  macos/scripts/run-swift-tests.sh TerminalUI DashboardFeature SessionFeature
```

| 対象 | ログの結果 | 終了 |
|---|---|---:|
| TerminalUI | Swift Testing 106件・20スイート成功 | 0 |
| DashboardFeature 本体 | Swift Testing 2140件・207スイート、既知問題1件。XCTestは4件中1件が既存条件でスキップ、失敗0 | 0 |
| DashboardFeature 実Git側 | Swift Testing 41件・4スイート成功 | 0 |
| SessionFeature | Swift Testing 1183件・131スイート成功 | 0 |
| 全件実行コマンド | `run-swift-tests: OK` | 0 |
| `xcodegen generate` | `/opt/homebrew/bin/xcodegen`、macosで1回実行 | 0 |
| 指定Debugビルド | `BUILD SUCCEEDED`、1回実行 | 0 |
| `git diff --check` | 指摘なし | 0 |

Debugビルドはmacosで次の指定どおり実行した。

```sh
xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug \
  -derivedDataPath /tmp/PhloxSTBuild build
```

元の失敗テストは最終全件でも0.329秒で成功し、追加テストも0.010秒で成功した。`PHLOX_TERMINAL_SNAPSHOT=1` による画面外描画は1回で、`macos/Packages/TerminalUI/.build/terminal-validation.png` を目視し、英字・日本語・色付き文字の描画を確認した。全ログは作業場所の `.build/st-crash-final-tests.log` と `.build/st-crash-debug-build.log` に保存した。

### 既存の問題・警告・未検証範囲

- DashboardFeature 本体のSwift Testingには既存の条件付きスキップ17件、XCTestにはRelease専用の性能計測のスキップ1件がある。テストの条件・期待値は変更していない。
- `GitHistoryWorkflowTests.swift:114` の `withKnownIssue` 内で、旧ブランチ名を再利用した後の並び順が期待と異なる既存問題1件を記録した。実際は `[main, new-topic, unused, old-topic]`、期待は `[main, new-topic, old-topic, unused]`。既存の既知問題として終了0だが、この問題は解決していない。当該ファイルに差分はない。
- Debugビルドの警告は2件で、どちらも `Metadata extraction skipped. No AppIntents.framework dependency found.`。LaunchServicesの再登録フェーズを毎回実行する旨の既存noteもある。
- 対象向けの独立したlint・型チェック・静的解析の設定は見つからず、未設定として扱う。Swiftの型検査はテストの再コンパイルとDebugビルドに含まれる。
- 実アプリ起動、実機のキー操作、XCUITestは実行していない。アプリの終了・再起動、入力ソース設定の変更、Gitのコミット・stash・ブランチ切り替え・マージも実行していない。
- 依頼項目（単独再現・スタック取得・原因特定・生成物の修復・回帰テスト・資料・指定の最終検証）に未実施はない。製品コードの変更は不要と判断した。Swiftコンパイラ／SwiftPM本体の依存追跡問題は未修正で、今後のSwiftTerm構造変更時にも依存パッケージのクリーンが必要になる。
