---
status: completed
last-verified: 2026-10-04
---

# 0040: 判断と最終状態

シンタックスハイライトを実装し、既定検査・Debug ビルド・UI テスト用ビルド・画面外描画・Release の13例を検証した。基準は [仕様](../specs/syntax-highlighting.md) に置く。

## 判断

- ファイルの未知種類は plain、チャットの未指定・未知フェンスは従来の Swift 走査を保持する。互換経路へ長行・サイズの制限を掛けず、既知言語の制限は維持する。
- ダークのキーワード #FC5FA3 と文字列 #FC6A5D は Xcode の既定テーマ・既存コード表示に揃えて維持する（仕様§4）。色割当は SessionFeature の公開部品で共有する。
- 全文の背景計算・50 ms 待機・一時的な前景属性・差分反映を維持する。日本語変換の置換は長さを記録し、変換中も適用履歴を残す。同じ本文への置換も再反映する。
- シェル代入は引用付きの値まで読み、次のコマンド位置を保持する。名前内のハイフンは引用符の境界とは別の旗で扱い、編集通知の単数版は複数範囲版へ委譲する。
- Markdown の全ブロックを Markdown として編集欄へ渡し、front matter の YAML への切替は共有規則で行う。Simulator の Debug 専用テストは Release の測定時にもコンパイル可能な既存の区分を維持する。
- 見本3c・3e・4j・4mの行番号・20pt行間・余白・編集面・輪・案内を維持する。plain・太字の見せ方は仕様§4に従い、本文データの差を画素の完全一致とは扱わない。

## 検証

既定検査: AgentDomain 587、DesignSystem 193、MessageStore 42、SessionFeature 1217、DashboardFeature 1987＋実Git26、SimulatorBridgeKit 16＋XCTest3。実行4056件成功、条件未実行15件、失敗0件。
字句回帰7件・編集属性15件成功（既定検査にも含む）。画面外描画2件・Release性能2件成功。Debug／PhloxUITests build-for-testing は exit 0、UI実走なし。
ビルドの派生データは `.build/DD` と `.build/PhloxUIBatch`。`git diff --check` 成功、凍結対象40ファイルの内容不変。独立した lint・型チェック・静的解析ゲートは未設定。以下は worktree ルートで再現する。既定スクリプトは実Gitテストを別パスで実行し、両方の成功を要求する。
既存の AppIntents 警告あり。

```bash
SWIFT_TEST_OUTPUT=full ~/.agents/scripts/compact-test --full syntax-r3-all-final bash macos/scripts/run-swift-tests.sh
PHLOX_SYNTAX_PERFORMANCE=1 ~/.agents/scripts/compact-test --full syntax-r3-performance swift test --package-path macos/Packages/DashboardFeature -c release --no-parallel --filter CodeSyntaxPerformanceTests
PHLOX_DESIGN_SNAPSHOTS=1 PHLOX_DESIGN_SNAPSHOT_SCOPE=syntax ~/.agents/scripts/compact-test --full syntax-r3-snapshots swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter DesignSnapshotRenderTests
```

## 性能測定

Mac16,8 / Apple M4 Pro / arm64、macOS 26.6.2（25G83）、Swift Package Release。10回のウォームアップ後、先頭・中央・末尾で100操作。数値はms、各操作のp95。入力・属性反映16ms以下、完了150ms以下を13例で満たした。

| 種類 | バイト数 | 入力 | 属性適用 | 完了 | 背景計算 | 判定 |
|---|---:|---:|---:|---:|---:|---|
| Swift | 10,000 | 0.73 | 0.31 | 53.98 | 0.76 | 達成 |
| Swift | 100,000 | 1.27 | 1.41 | 57.99 | 4.32 | 達成 |
| Swift | 1,000,000 | 5.78 | 7.94 | 90.41 | 26.97 | 達成 |
| Swift・日本語確定 | 1,000,000 | 0.46 | 7.80 | 88.82 | 28.10 | 達成 |
| JSON | 10,000 | 0.84 | 2.19 | 54.67 | 0.75 | 達成 |
| JSON | 100,000 | 0.74 | 1.96 | 59.33 | 4.94 | 達成 |
| JSON | 1,000,000 | 2.57 | 11.36 | 96.41 | 31.94 | 達成 |
| Markdown | 10,000 | 0.74 | 0.21 | 54.94 | 0.93 | 達成 |
| Markdown | 100,000 | 1.27 | 1.08 | 59.35 | 5.50 | 達成 |
| Markdown | 1,000,000 | 8.64 | 7.77 | 105.12 | 38.91 | 達成 |
| 混在 | 10,000 | 0.71 | 1.73 | 54.96 | 1.76 | 達成 |
| 混在 | 100,000 | 1.60 | 1.46 | 64.05 | 10.36 | 達成 |
| 混在 | 1,000,000 | 11.19 | 9.62 | 138.47 | 73.18 | 達成 |

初回同期予約・初回属性適用・テーマ切替同期更新・テーマ切替属性適用の最大値は 0.03／9.00／6.70／7.10 ms（各16ms以下）。日本語確定は窓なしの NSTextView で、変換範囲の置換後に確定する経路を測定した。

ライト／ダーク36枚を `.build/design-snapshots/` へ生成した。シェルのライト／ダーク2枚を目視確認し、代入・文字列・コマンド・オプションの色を確認した。
TSX・CSS・YAML・ログ・Pythonの境界を含む本文と、文字列／コメント内のキーワード・未閉鎖文字列を含む既存の撮影例は維持する。4mの実画面のアクティブ選択色は未検証。

## 未検証事項

既定検査の条件未実行15件のうち性能1件はReleaseで実行済み。残る実アプリ・端末入出力等の14件と、実際の日本語入力候補画面・物理入力は未検証。
UIテストはビルドのみ。PM向け実行指定は `-only-testing:PhloxUITests/MarkdownBlockInteractionTests/testSourceHighlightingKeepsUndoAndSavedBytes` と `-only-testing:PhloxUITests/MarkdownBlockInteractionTests/testBlockEditingSaveAndModes`。
