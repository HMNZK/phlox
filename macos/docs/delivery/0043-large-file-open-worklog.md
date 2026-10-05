---
status: completed
last-verified: 2026-10-05
---

# 大きいファイルの編集・閲覧

r5で再レビューの4項目を修正した。入力の巻き戻りを防ぎ、CRLFへの変更を描画比較で検出し、色付け判定と上限文言を改善した。5 MBの入力→描画p95は61.0 ms（r4は86.6 ms）。既定テスト・Release性能・画面外描画・Debugビルド・UI build-for-testingは成功し、21画像はr4と同一。変更は未コミットで残す。

## PM の最終修正と検証（r5 の後）

- **閉じるときの固まりを修正**
  - 症状: 約 2MB・50 万行の閲覧のみの文書を開いたままアプリを終了すると、10 秒以上応答しなかった（UI テストの終了待ち 10 秒を超えた）。
  - 原因（`sample` で確認）: 編集欄を破棄するときの再描画要求で、AppKit が非連続レイアウトの穴を全文埋め直していた。経路は `CodeTextEditor.dismantleNSView → removeBlockEditor → removeFromSuperview → _ensureLayoutCompleteForVisibleRect… → _NSFastFillAllLayoutHolesForGlyphRange`。
  - 修正: `dismantleNSView` で、外す前に本文と組版を切り離す（`removeLayoutManager`）。
  - 確認: UI テスト `testLargeFileReadOnlyKeepsSelectionAndSavedBytes`（50 万行）が、修正なしでは終了待ちで失敗し、修正ありでは成功する。AppKit 単体と画面外の単体テストでは同じ固まりを再現できなかったので、単体テストは追加していない。
  - 途中で `testLargeHTMLSourceEditsSavesAndUndoes` が失敗し、修正の副作用と誤って判断した。実際の原因は、日本語入力の入力モード表示（84×77 のダイアログ）が XCUITest の操作に割り込んだことで、修正とは関係なかった。入力ソースを英字にすると、修正ありで 7 件すべて成功した。
- **入力の巻き戻りの回帰テストを補強**: 親を作り直さずに環境だけが変わる更新でも入力が巻き戻らないことを確かめる `environmentOnlyUpdateWithOldStructKeepsTypedText`。生成時に 1 回だけ読む変異で失敗することを、レビュアーが確認した。
- **UI テストの前提を修正**:
  - 帯の案内文は AX の value で確かめる。
  - コピーは全選択で確かめる。
  - 検索欄はシステム共通の検索語を引き継ぐので、開く前に消す。
  - 検索語は一意な文字列にする。
  - 検索欄への入力はアプリ全体に送る。
- 試して取り消したもの: 大きい本文で、入力ごとに一致をすべて強調する検索（incremental search）を止める変更。効果を確認できなかったため取り消した。
- **PM の最終検証（2026-10-06、最終コード）**
  - `run-swift-tests.sh`: Swift Testing 4,107 件が成功、失敗 0。
  - Debug ビルド: 成功。
  - UI テスト 7 件が成功（MarkdownBlockInteractionTests 6 件・FileTreeInteractionTests 1 件。入力ソースは英字）。
  - Release の `LargeFilePerformanceTests|CodeSyntaxPerformanceTests` は 4 件成功。実 6.6MB は開くまで 417.6ms、スクロール p95 30.2ms・最大 31.0ms。5MB の入力から描画まで p95 60.8ms。ただしこの測定は、破棄時の切り離しを `removeBlockEditor` 側に置いていた版で行った。最終版では同じ処理を `dismantleNSView` へ移している。
  - 撮影（large-files）: 成功。変更パネルの 4 枚だけ r5 と差があり、差は gh コマンドの有無による下部の案内文だけだった。

## r5の依頼と設計の対応

| 再レビューの項目 | 設計の節 | 対応状況 |
|---|---|---|
| 1. 古い本文による入力の巻き戻り | ファイル編集§3.2・§3.4・§6、ADR0181の決定 | 直した。CodeTextEditorは文書の最新値を読む／書く関数を直接受け取り、Bindingを保持しない。ファイルタブ・ブロック編集・既存の検査を同じ入口へ移行。全文比較を避ける効果を保ち、ADRの14行目を更新 |
| 2. CR直後へのLF挿入と行番号の変異検査 | ファイル編集§3.8・§6、ADR0181の決定・検証 | 直した。既存のCR条件で、最初に位置3へLFを挿入してCRLFにし、新規エディターの行番号画像と比較。差分更新の「-2→-1」を検出 |
| 3. 色付け可否の全文走査 | NFR-5、色付け仕様§5、ADR0181 | 直した。NSStringのUTF-16長が上限超なら偽、長さ×3が上限以内なら真。それ以外だけUTF-8長を数える。ASCII・日本語・絵文字とBOMの6条件でバイト境界と一致を検査 |
| 4. テスト表・上限文言 | ファイル編集§3.8・§6 | 直した。ReadOnlyTextTestsと5 MB超の閲覧のみの境界をテスト表へ追加。ファイルタブ・変更パネルとも編集上限の定数を翻訳書式へ渡す。ja/enの表示文言はr4と同じ |

## r5の再現・変異検査

- 基準版HEAD `ba9dc57b735563375fad282f0b8b364ce365f3fc` をworktree内の`.build/r5-base`へ展開し、提示されたBindingの再現テストを追加して実行。1テスト成功、失敗0。検証用コピーは終了後に削除し、再現テストを`.build/r5-before/ReusedBindingRegressionTests.swift`に残した。
- 修正前のr4差分では同じ再現テストが1件失敗（exit 1）。パスを変えた後、表示は`let value = 42`に戻る一方で保存先は`xlet value = 42`だった。
- 修正後は入口を関数へ変更したため、同じアクセス関数を再利用する`reusedTextAccessDoesNotRevertTypedText`として同じ操作・比較を保持。次の打鍵も追加して入力が残ることを検査。閲覧のみ／省略表示から編集可へ戻す検査も追加した。
- 行番号の「-2→-1」変異は、CR直後へのLF挿入条件で1件失敗（exit 1）。元へ戻した後、LF・CRLF・CR・Unicode改行の4条件が成功した。変異は最終コードに残していない。
- API切替直後の絞込み検査は、旧Coordinatorの呼出しと削除したbinding変数への参照が残っていたためコンパイル失敗。呼出側を移行し、絞込み32テストと最終の既定全数で成功した。期待値は弱めていない。

## r5の性能（最終コード）

Apple M4 Pro / Mac16,8 / 24 GiB、macOS 26.6.2（今回sysctl・sw_versと性能ログで確認）。Release、本番FileTabView、画面外800×600 pt。編集は先頭・中央・末尾で各25回、準備5回を除く60回の入力→cacheDisplay。閲覧スクロールは初回を含む75位置。実キー・ホイール・GPU合成の時間ではない。

| 文書 | バイト数 | 読込／拒否 ms | 開く ms | 入力→描画 p95 ms | スクロール p95／最大 ms |
|---|---:|---:|---:|---:|---:|
| 1MB.swift | 1,000,000 | 5.0 | 639.5 | 31.9 | — |
| 2MB.swift | 2,000,000 | 10.0 | 118.7 | 33.3 | — |
| 5MB.swift | 5,000,000 | 23.2 | 227.7 | 61.0 | — |
| 10MB.swift（閲覧のみ） | 10,000,000 | 64.7 | 461.7 | — | 23.1／23.4 |
| 20MB.swift（閲覧のみ） | 20,000,000 | 132.0 | 874.9 | — | 23.7／35.4 |
| 50MB.swift（読込拒否） | 50,000,000 | 14.1 | — | — | — |
| real-550KB.html | 550,139 | 4.5 | 94.3 | 30.1 | — |
| real-6.6MB.html（閲覧のみ） | 6,662,855 | 367.2 | 419.8 | — | 30.3／31.4 |

生データは`.build/large-file-performance/document-r5-final.json`。5 MBの入力だけのp95は0.560 ms、入力→描画p95は61.042 ms。r4の86.6 msから下がった。測定した編集可の4文書は入力→描画p95 ≤ 100 msを満たし、実6.6 MBの初回を含むスクロール最大 ≤ 100 msも成功した。

色付け13条件は基準達成。入力p95の最大3.4 ms、属性適用p95の最大11.2 ms、完了p95の最大136.7 ms。生データは`.build/r5-syntax-performance.json`（検証終了後にコピー）と`.build/syntax-performance.json`。

長い行の文字形回帰は4条件成功。準備済み基準／変更後の中央入力は、貼付け878.8／876.9 ms、フォント877.0／882.6 ms、外部同期879.6／880.9 ms、1 MB境界通過1,633.8／1,559.5 ms。準備済み基準の2倍以内という既存基準の検査であり、5 MB以下の長い行の快適さを保証する数値ではない。

## r5で変更したファイル

今回新しく追加した製品・テスト・資料ファイルはない。r4までの未コミット差分を維持し、次の16ファイルを変更した。

- `macos/App/Localizable.xcstrings`
- `macos/Packages/DashboardFeature/Sources/DashboardFeature/Tabs/{CodeTextEditor,MarkdownBlockEditor,SessionTabsContainer}.swift`
- `macos/Packages/DashboardFeature/Sources/DashboardFeature/Editor/EditorPanelViewModel.swift`
- `macos/Packages/DashboardFeature/Sources/DashboardFeature/WorkingTree/WorkingTreeService.swift`
- `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/{CodeTextEditorTests,CodeSyntaxHighlightsTests,CodeSyntaxPerformanceTests,LargeFileEditingTests,LargeFilePerformanceTests,FileTabUndoScopeTests,MarkdownBlockEditorLifecycleTests}.swift`
- `macos/docs/adr/0181-large-text-files-without-highlighting.md`
- `macos/docs/specs/file-explorer-and-markdown-editing.md`
- `macos/docs/delivery/0043-large-file-open-worklog.md`

## r5の検証コマンドと結果

テスト・両ビルドは`~/.agents/scripts/compact-test --full <ラベル> ...`経由。下表はラッパーへ渡したコマンド。ビルドとxcodegenはworktreeのmacos内で実行した。

| コマンド | 結果 | ログ |
|---|---|---|
| `swift test --package-path .build/r5-base/macos/Packages/DashboardFeature --no-parallel --filter reusedBindingDoesNotRevertTypedText` | 基準版1テスト成功・失敗0 | `.build/r5-base-binding.log` |
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter reusedBindingDoesNotRevertTypedText` | 修正前1テスト失敗（期待した再現、exit 1） | `.build/r5-binding-red.log` |
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter codeEditorRefreshesLineNumbersAfterTextChanges` | 「-2→-1」の変異でCR条件1件失敗（exit 1） | `.build/r5-line-number-mutation.log` |
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter 'reusedTextAccessDoesNotRevertTypedText\|codeEditorTogglesEditabilityWithoutWritingDisplayBack\|codeEditorRefreshesLineNumbersAfterTextChanges\|highlightingFastPathsMatchByteBoundary'` | 修正後4テスト成功・失敗0。切替2・行番号4・上限6の引数違いも実走 | `.build/r5-regression-green.log` |
| `env SWIFT_TEST_OUTPUT=full bash macos/scripts/run-swift-tests.sh` | 既定6パッケージ＋実git別パス成功。Swift Testing集計4,106件（条件付きskip17件）、XCTest成功6件・既存skip1件、失敗0 | `.build/r5-default-tests.log` |
| `env PHLOX_LARGE_FILE_PERFORMANCE=1 PHLOX_SYNTAX_PERFORMANCE=1 PHLOX_LARGE_FILE_LABEL=r5-final swift test -c release --package-path macos/Packages/DashboardFeature --no-parallel --filter 'LargeFilePerformanceTests\|CodeSyntaxPerformanceTests'` | 4テスト成功・失敗0（391.313秒）。8文書・色付け13条件・文字形4条件 | `.build/r5-final-performance.log` |
| `env PHLOX_DESIGN_SNAPSHOTS=1 PHLOX_DESIGN_SNAPSHOT_SCOPE=large-files swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter DesignSnapshotRenderTests` | 2テスト成功・失敗0（12.892秒）。21画像を生成して直後にコピー | `.build/r5-design-snapshots.log` |
| `/opt/homebrew/bin/xcodegen generate` | 成功 | ツール出力 |
| `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /Users/ryosuke/Projects/Phlox-oss-worktrees/large-file-open/.build/DD build` | BUILD SUCCEEDED | `.build/r5-debug-build.log` |
| `xcodebuild -project Phlox.xcodeproj -scheme PhloxUITests -configuration Debug -derivedDataPath /Users/ryosuke/Projects/Phlox-oss-worktrees/large-file-open/.build/PhloxUIBatch build-for-testing` | TEST BUILD SUCCEEDED。UIテスト未実行 | `.build/r5-ui-build.log` |

独立したlint・静的解析は未設定。型の検査・コンパイル・リンクは全数テストと両ビルドで実行した。既定実行のskipは既存の環境条件付き14件と、別途Releaseで実行した性能3件。XCTestのskip1件は既存Release限定のMarkdownスクロール性能。スキップなしの全件実走とは扱わない。

Releaseや基準版のコンパイルには、既存の非推奨API・actor隔離・不要なtry・ViewBuilderとreturn等の警告がある。両ビルドには`Metadata extraction skipped. No AppIntents.framework dependency found.`とad-hoc署名のhardened runtime無効化の注記がある。ログに保持し、警告なしとは扱わない。

## r5の写真・判断・未検証

写真は`.build/large-file-design-snapshots-r5`の21 PNG。撮影成功の直後に`cp -R .build/design-snapshots .build/large-file-design-snapshots-r5`でコピーした。21枚をr4の同名画像とSHA-256で比較し、21枚とも完全一致した。

閲覧のみja/en、省略ja/en/light、320pt、変更パネルの閲覧のみ、20 MB超の計8画像を自分で開いた。見本3c・3lとr3/r4の判断に照らし、帯・上限文言・行番号・省略・保存無効・余白を確認した。21枚すべてを個別に目視したという意味ではない。今回の上限書式化による見た目の変更はない。

Bindingの再現テストは、製品APIの変更に合わせて関数を再利用する形へ移行した。基準版と修正前は提示されたBindingの形で実走し、修正後は同じアクセス先・入力・rootViewの更新・本文比較を保持した。

UI実行用はworktree内の`.build/PhloxUIBatch/Build/Products/PhloxUITests_macosx26.2-arm64.xctestrun`。共通の作業場所制約を優先したため、指定の`/tmp/PhloxUIBatch`へは出力していない。PMの実行対象は次の4つ（今回のUIテストソースは変更していない）。

```text
-only-testing:PhloxUITests/MarkdownBlockInteractionTests/testLargeFileReadOnlyKeepsSelectionAndSavedBytes
-only-testing:PhloxUITests/MarkdownBlockInteractionTests/testFileOverHardLimitShowsUnavailableState
-only-testing:PhloxUITests/MarkdownBlockInteractionTests/testLargeHTMLSourceEditsSavesAndUndoes
-only-testing:PhloxUITests/MarkdownBlockInteractionTests/testSourceHighlightingKeepsUndoAndSavedBytes
```

XCUITest・実キーによる検索／コピー・実ホイール・GPU合成・実HTMLレンダリングの性能・変更パネルの実画面の性能・ピークメモリは未検証。描画は画面外で行い、実アプリの起動・終了・前面化・computer-useは行っていない。

最終検証の前後でソース等1,197ファイルのSHA-256が一致した。作業開始時に存在した凍結対象40ファイルも一致した。`git diff --check`成功。commit・push・mergeは行わず、本体チェックアウト・.env*・0039〜0042・既存ADRは変更していない（今回新規の0181のみ更新）。

## 判断

- r5：再レビューの明示指示により今回の0043だけを再開する。Bindingの写しを本文の保管場所にせず、最新の本文を読む／書く入口へ改め、SwiftUIによる全文比較の回避を保つ。CRからCRLFになる編集の描画比較と変異検査、色付けのUTF-16長による早期判定、上限定数を渡す翻訳書式を追加する。表示文言・構成はr4と同じに保つ。UI build-for-testingも共通制約に従いworktree内の`.build/PhloxUIBatch`へ出力する（/tmpへの書込み指定より作業場所の制約を優先）。
- r4：今回の明示指示により0043だけを再開する。0039〜0042と既存ADRは変更しない。閲覧のみのソース表示に限り、改行を除く10,000 UTF-16単位超の行を省略する。しきい値はChatCodeTokenizerと共有し、境界をまたぐ書記素は手前から省略する。Nは隠した書記素（Swift Character）の数。元の本文・BOM・読込バイトは保持し、コピー・検索は省略後の表示を対象にする。
- r4：省略は読込時に一度だけ準備し、ja/enの目印は既存の翻訳経路、色はtextTertiaryを使う。帯への追記は省略したソースを表示しているときだけ。HTMLのレンダリングは元の本文を使う。見本に省略状態がないため、既存ソースの余白・行間・折返し・帯を維持して撮影状態を追加する。
- r4：実6.6 MBのReleaseスクロール計測は初回を含む75位置を維持し、最大100 ms以下を検査する。最終状態の欄はr4の最終コードで得た結果だけへ置き換える。UIテストはbuild-for-testingのみ。指定された/tmp/PhloxUIBatchは出力先の例外とする。
- r3：編集上限5,000,000バイト・閲覧上限20,000,000バイト・色付け上限1,000,000バイトをWorkingTreeTextへ集約する。BOM込みの読込時サイズで判定する。10 MB149.8 ms／20 MB288.3 ms／実6.6 MB991.6 msという入力→描画p95を根拠に、5 MB超は入力を止めて閲覧を残す。
- r3：閲覧のみは既存NSTextViewのisEditable=false・isSelectable=trueを使い、検索・選択・コピー・スクロールを残す。文書側でもdraftの変更・保存・上書き・dirty・ブロック編集・undoを拒否する。編集中に5 MBを超えた文書は従来どおり保存でき、次の新規読込で閲覧のみになる。
- r3：外部変更は既存のソース文書と同じくタブを閉じて開き直すまで反映しない（loadIfNeededは未読込時のみ）。HTMLは既存の安全なレンダリングと再読込を保つ。Markdownの5 MB超はソース固定。変更パネルは再選択で読み直し、5 MB超でも20 MBまで内容を閲覧でき、20 MB超は変更プレビューのみを残す。
- r3：見本3lの構成を維持して上限表示を20 MBへ変更する。新しい閲覧のみ状態は同じ帯の案内部品で「閲覧のみ（5 MB を超えるため）」と表示し、狭い幅は既存どおり情報アイコンに縮める。HTMLのレンダリングでもサイズによる閲覧のみの案内を出す。
- r3：撮影で20MB+の文字が既存30ptのアイコン枠へ近づきすぎたため、サイズ超過の枠だけ36ptへ広げる。外側40pt・高さ・文字サイズ・中央配置は維持する。説明の「編集できる」は編集上限5 MBと矛盾するため「開ける」へ変更する。
- r3：今回の指示で0043を再開する。完了済み0039〜0042には追記しない。実HTML不在時のRelease文字形回帰だけは指定どおり条件付きでスキップする。
- r3：HTMLの「再読込」は保存中の文書スナップショットを再描画する既存経路であり、外部ディスク変更を取り込む操作ではない。外部変更を反映するにはHTMLもタブを開き直す。準備失敗時もソース閲覧のみを保ち、補足文言を編集可と表示しない。
- r3：画面外のコピー検査は専用ペーストボードとNSTextView.writablePasteboardTypesを使い、利用中の一般ペーストボードを書き換えない。検索は既存のAppKit検索バーを有効にする。実キー入力による検索UIはPMのUIテストで検証する。
- r3：画面外のコード経由で⌘Fを入力しても、検索バーの設定だけでは3条件とも帯が開かなかった。既存ソースビューのkeyDownからAppKitの検索アクションへ渡す入口を加える。グローバルなキー送信や新しい検索部品は作らない。
- r3：変更パネルの境界は復号した本文のUTF-8バイト数（BOMを含む。decodeUTF8は原バイトと一致を検査）で判定する。別のfileSize取得は不要なので外し、読込後の外部変更でサイズ判定がずれる経路も減らす。
- r3時点では色付けなしの文字形準備、差分で更新する行番号、保存時のUTF-8符号化、NSStringによる同期・dirty比較、Bindingの参照型保持をr2から維持した。Bindingの保持はr5で最新値を読む／書く関数へ置き換えた。
- r3：初回Release計測の実6.6 MBは開く449 ms・スクロールp95 32.6 msに対して最大11.1秒の停止を観測した。成功という語だけで応答性を断定しない。最遅の移動位置と移動／描画の時間を分けて計測し、長い1行のTextKit初回レイアウトかを確認する。見本の折返しや既存NSTextViewを変更する回避策は採らない。
- r3：HTMLレンダリング撮影の合成データは5 MB超を保ち、既存サンプルの見える本文と1つの大きいコメントにする。多数のコメントによるDOM作成は帯の描画検査に不要。読み込み完了の待機と18状態の撮影数の検査は弱めない。

## 依頼と設計の対応

| 依頼 | 設計の節 | r4の対応状況 |
|---|---|---|
| 長い行の省略と共有しきい値 | ファイル編集NFR-5・§3.8、ADR0181、色付け仕様§5 | 対応。ChatCodeTokenizer.maximumLineUTF16Length（10,000）を共有し、読込時に一度だけ表示用の省略を準備 |
| 書記素境界・省略数・ja/en・色 | ファイル編集§3.8、ADR0181 | 対応。境界をまたぐ書記素は手前から省略。Nは隠したSwift Character数。既存翻訳とtextTertiaryを使用 |
| 原文・バイト・保存・外部変更・編集可ファイル | ファイル編集NFR-1・NFR-5・§3.2、architecture | 対応。draft・loadedDiskBytes・BOMを保持し保存／上書きを拒否。外部変更は従来どおり開き直し。5 MB以下は省略しない |
| コピー・検索・帯 | ファイル編集§3.8、ADR0181 | 対応。NSTextViewの文字列は表示用だけ。省略があるソース表示の帯にだけ案内を追加。HTMLレンダリングは原文を使用 |
| 境界・CRLF・複数行・コピー・バイト保持の検査 | ファイル編集§6、ADR0181 | 対応。ReadOnlyTextTestsの5テスト（10,000／10,001と絵文字／結合文字の引数違いも実行）。既定全数で成功 |
| 実6.6 MBの性能 | NFR-5、ADR0181 | 対応。Release、本番FileTabView、初回を含む75位置。最大100 ms以下の検査を追加し成功 |
| 省略状態の撮影 | ファイル編集§3.8、見本3c・3l、本記録の判断 | 対応。ja/en/lightの3状態を追加、large-filesの21画像を再生成して直後に専用フォルダへコピー |
| UIテスト・全数・ビルド・資料 | ファイル編集§6、ADR0181 | 対応。既存UIテストに省略確認を追加。既定全数・Debug・UI build-for-testing成功。UIテスト実行はPMへ引き継ぐ |

## r4時点の性能（過去の記録）

Apple M4 Pro / Mac16,8 / 24 GiB、macOS 26.6.2（r4でsysctl・sw_versを確認）。Release、画面外800×600 pt、本番FileTabView。編集は先頭・中央・末尾で各25回から準備5回を除く60回の入力→cacheDisplay。閲覧スクロールは文書全体の75位置へ移動し、初回を除かずscrollRangeToVisible→cacheDisplayを測る。実キー・ホイール・GPU合成の時間ではない。

| 文書 | バイト数 | 読込／拒否 ms | 開く ms | 入力→描画 p95 ms | スクロール p95／最大 ms | 状態 |
|---|---:|---:|---:|---:|---:|---|
| 1MB.swift | 1,000,000 | 5.2 | 645.1 | 34.9 | —／— | 編集可 |
| 2MB.swift | 2,000,000 | 10.4 | 132.2 | 43.6 | —／— | 編集可 |
| 5MB.swift | 5,000,000 | 25.5 | 252.6 | 86.6 | —／— | 編集可 |
| 10MB.swift | 10,000,000 | 66.9 | 460.5 | — | 25.2／25.5 | 閲覧のみ |
| 20MB.swift | 20,000,000 | 141.2 | 919.0 | — | 25.4／25.8 | 閲覧のみ |
| 50MB.swift | 50,000,000 | 14.3 | — | — | —／— | 読込拒否 |
| real-550KB.html | 550,139 | 4.3 | 102.8 | 35.6 | —／— | 編集可 |
| real-6.6MB.html | 6,662,855 | 380.2 | 439.1 | — | 32.0／43.1 | 閲覧のみ |

生データは `.build/large-file-performance/document-r4-final.json`。実6.6 MBは開く439.1 ms・スクロールp95 32.0 ms・最大43.1 msで、初回を含む最大100 ms以下の検査が成功した。最遅移動3.9 ms・続く描画39.2 ms。読込380.2 msには表示用の省略準備も含む。128行目は改行を除き4,172,954 UTF-16単位（r4で実ファイルを再計数）。原文を変更せず、表示だけを短くして長い段落の組版を避ける。最初の1 MBの「開く」はAppKit初期化を含む。

CodeSyntaxPerformanceTestsは13条件で基準達成。入力p95の最大3.5 ms、属性適用p95の最大11.6 ms、色付け完了p95の最大131.7 ms。生データは `.build/syntax-performance.json`。

文字形のRelease回帰も4条件成功。準備済み基準／変更後の中央入力は、貼付け952.0／956.3 ms、フォント953.2／951.9 ms、外部同期963.5／967.9 ms、1 MB境界通過936.9／1,649.0 ms。これは編集可能なCodeTextEditorの既存回帰で、基準の2倍以内を検査する。5 MB以下の長い行の応答性を保証するものではない。

## 追加・変更したファイル（r4）

追加：
- `macos/Packages/DashboardFeature/Sources/DashboardFeature/Tabs/ReadOnlyText.swift`
- `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/ReadOnlyTextTests.swift`

変更（既存のr3差分を維持）：
- `macos/App/Localizable.xcstrings`
- `macos/Packages/AgentDomain/Sources/ChatRenderKit/ChatCodeLanguage.swift`
- `macos/Packages/DashboardFeature/Sources/DashboardFeature/Tabs/{CodeTextEditor,FileTabDocument,SessionTabsContainer}.swift`
- `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/{LargeFilePerformanceTests,DesignSnapshotRenderTests}.swift`
- `macos/UITests/MarkdownBlockInteractionTests.swift`
- `macos/docs/adr/0181-large-text-files-without-highlighting.md`（今回の作業で新規作成されたADRを更新）
- `macos/docs/specs/file-explorer-and-markdown-editing.md`
- `macos/docs/architecture/file-explorer-and-markdown-editing.md`
- `macos/docs/delivery/0043-large-file-open-worklog.md`

## r4時点の検証（過去の記録）

以下はすべて `~/.agents/scripts/compact-test --full <ラベル> ...` 経由。環境変数はラッパー後のenvで渡した。コード・翻訳471ファイルのSHA-256は検証開始後に変わっていない。

| コマンド | 結果 | ログ |
|---|---|---|
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter ReadOnlyTextTests` | 5テスト成功（引数違いも実行）・失敗0 | `.build/r4-boundary-tests.log` |
| `SWIFT_TEST_OUTPUT=full bash macos/scripts/run-swift-tests.sh` | 既定6パッケージ＋実git別パス成功。Swift Testing集計4,103件（条件付きskip17件）、XCTest成功6件・既存skip1件、失敗0 | `.build/r4-default-tests.log` |
| `PHLOX_LARGE_FILE_PERFORMANCE=1 PHLOX_SYNTAX_PERFORMANCE=1 PHLOX_LARGE_FILE_LABEL=r4-final swift test -c release --package-path macos/Packages/DashboardFeature --no-parallel --filter 'LargeFilePerformanceTests\|CodeSyntaxPerformanceTests'` | 4テスト成功・失敗0（392.643秒）。8文書、色付け13条件、文字形4条件 | `.build/r4-final-performance.log` |
| `PHLOX_DESIGN_SNAPSHOTS=1 PHLOX_DESIGN_SNAPSHOT_SCOPE=large-files swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter DesignSnapshotRenderTests` | 2テスト成功・失敗0（13.046秒）。21画像を生成して直後にコピー | `.build/r4-design-snapshots.log` |
| `/opt/homebrew/bin/xcodegen generate`（macos内） | 成功。worktree内へ生成 | ツール出力 |
| `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath <worktree>/.build/DD build`（macos内） | BUILD SUCCEEDED | `.build/r4-debug-build.log` |
| `xcodebuild -project Phlox.xcodeproj -scheme PhloxUITests -configuration Debug -derivedDataPath /tmp/PhloxUIBatch build-for-testing`（macos内） | TEST BUILD SUCCEEDED。UIテストは未実行 | `.build/r4-ui-build.log` |

独立したlint・静的解析は未設定。コンパイル・リンクは全数テストと両ビルドで検査した。通常実行のSwift Testingのskip17件は既存の環境条件付き14件と、別途Releaseで実行した性能3件。XCTestのskip1件は既存Release限定のMarkdownスクロール性能。通常実行をスキップなしの全件実走とは扱わない。

既存の非推奨API・actor隔離・未使用戻り値／不要なtry・ViewBuilderとreturnのコンパイル警告をログに保持した。Debug・UIビルドには `Metadata extraction skipped. No AppIntents.framework dependency found.`、ad-hoc署名のhardened runtime無効化の注記がある。警告なしとは扱わない。既定テスト内のworktree／未マージブランチの削除拒否は、既存の拒否表示を検査するテストで発生し、そのテストは成功した。

## 写真と確認

`.build/large-file-design-snapshots-r4` に21 PNG。撮影直後に `cp -R .build/design-snapshots .build/large-file-design-snapshots-r4` で保存した。既存の撮影元は `.build/design-snapshots-before-r4` に退避して保持した。

新しい省略状態のja/en/lightを自分で開き、見本3cのソース構成と今回の判断に照らして確認した。末尾の目印が本文とは異なるtextTertiaryで表示され、次の行番号が3のまま残る。帯の案内はja/enとも収まり、保存は無効。通常閲覧ja/en・320ptと20 MB超ja/enも開き、見本3lの構成とr3の判断を維持していることを確認した。既存18 PNGは前回の画像とSHA-256が完全一致している。21画像すべてを個別に目視したという意味ではない。画面操作はしていない。

## PMが実行するUIテスト

`/tmp/PhloxUIBatch/Build/Products/PhloxUITests_macosx26.2-arm64.xctestrun` に対して以下を指定する。今回更新したのは先頭のテストで、長い行の省略表示・帯・隠した末尾の不在を確認する検査を追加した。実入力を伴うため実行はしていない。

```text
-only-testing:PhloxUITests/MarkdownBlockInteractionTests/testLargeFileReadOnlyKeepsSelectionAndSavedBytes
-only-testing:PhloxUITests/MarkdownBlockInteractionTests/testFileOverHardLimitShowsUnavailableState
-only-testing:PhloxUITests/MarkdownBlockInteractionTests/testLargeHTMLSourceEditsSavesAndUndoes
-only-testing:PhloxUITests/MarkdownBlockInteractionTests/testSourceHighlightingKeepsUndoAndSavedBytes
```

## 判断・未検証・制約

見本にない省略状態は「判断」に先に書いた既存部品の構成で実装した。省略数NはUTF-16単位数ではなく、隠した書記素数。帯の追記は省略したソースを表示中だけで、HTMLレンダリングには加えない。コピー・検索は表示文字列のみを対象とする。

XCUITest・実キーによる検索／コピー・実ホイール・GPU合成・変更パネルの実画面の性能・実HTMLレンダリングの性能・ピークメモリは未検証。画面外での表示文字列コピー、検索バー設定、本文／バイト保持、保存拒否、外部変更後の開き直しはテストで確認した。5 MB以下の長い行は従来のまま省略せず、快適さを保証しない。実ファイル不在時の既存Release回帰の条件式は維持し、不在環境では実走していない。

commit・push・merge・実アプリ起動・XCUITest実行は行っていない。本体チェックアウト・稼働中アプリ・.env*・凍結ファイル・0039〜0042・既存ADRは今回変更していない（今回新規の0181だけ更新）。

## 記録

- r5：再レビュー4項目を修正。基準版の入力検査成功、修正前の巻き戻りと行番号「-2→-1」を各1件の失敗で確認し、修正後に成功。5 MBの入力→描画p95は61.0 ms。既定Swift Testing集計4,106件（skip17件）、XCTest成功6件・skip1件、Release4テスト・撮影2テスト・Debug・UI build-for-testing成功。21画像を直後に専用フォルダへコピーし、r4と21枚一致。判断は本文へのアクセス関数化とUI出力先のworktree内への統一。変更は未コミット。
- r4：最終コードのRelease4テスト成功。実6.6 MBの初回を含む75位置はp95 32.0 ms・最大43.1 ms。既定Swift Testing集計4,103件（skip17件）、XCTest成功6件・skip1件、失敗0。撮影21画像を直後に専用フォルダへコピーし、省略ja/en/lightを目視。既存18画像は前回と完全一致。Debug・UI build-for-testing成功。最終状態にはr4の値だけを記載。
- r4：資料へ省略の判断を先に追記。共有定数・読込時の表示準備・ja/enの目印・textTertiary・省略時だけの帯追記を実装。境界と書記素・CRLF・複数長行・原文／バイト保持・コピー・保存拒否・編集可ファイルの対象外を登録し、5テスト成功（引数違いも実行）。省略が見えるja/en/lightの3状態を撮影へ追加。Debug buildとUI build-for-testing成功。最終コード・翻訳471ファイルのハッシュを記録して既定検証中。
- r3：最終Debug build・UI build-for-testing成功。最終検証前に固定した17コード／翻訳ファイルのSHA-256と検証後の値が一致し、git diff --checkも成功。凍結ファイル・0039〜0042・.env*への差分なし。資料を最終結果へ更新し、実キー操作はPMへ引き継ぐ。
- r3：最終Releaseの4テスト成功（414.691秒）。実6.6 MBは開く440.6 ms・スクロールp95 35.1 ms・最大10,534.6 ms。最遅移動10,505.5 msは長い128行目に初めて入る位置で、描画29.1 msとは分離できた。色付け13条件・文字形4条件も成功。
- r3：最終コードの既定テストが成功。6パッケージ＋実git別パス、Swift Testingのサマリー4,098件（条件付きskip表示17件）、XCTest成功6件・既存Release限定skip1件、失敗0。性能は別途Releaseで実行した。変更中の17コード／翻訳ファイルのSHA-256を固定して検証を継続した。
- r3：撮影用HTMLを1つの大きいコメントへ変更して18状態が成功。画像の比較後、20MB+の枠幅だけ36ptへ変更して最終撮影も2テスト成功（11.123秒、18画像）。直後に専用フォルダへコピーし、最終3l ja/enとHTMLレンダリングを再目視。他15PNGは初回コピーと完全一致。
- r3：最初の撮影は18状態中17画像を生成し、HTMLレンダリングの10秒待機が未完了で1件失敗。生成画像を直後に `.build/large-file-design-snapshots-r3-first` へコピーした。5 MB超という前提と18状態の検査を保ち、撮影用HTMLの多数のコメントを1つのコメントへまとめて再実行する。
- r3：最初のReleaseは4テスト成功。8文書を本番経路で測り、実6.6 MBを閲覧のみで受入。開く449.0 ms・スクロールp95 32.6 ms・最大11,101.8 ms。最大遅延の切分けを追加し、最終コードで再計測する。初回ログは `.build/r3-first-performance.log`、データは `.build/large-file-performance/document-r3-first.json`。
- r3：検索バーの有効化だけでは⌘Fの3条件が失敗。既存keyDownからAppKit検索へ渡す入口を追加した同じ3条件と変更パネル境界の検査が成功（7テスト、失敗0）。別のfileSize取得を削除し、BOM込み本文バイト数で判定するKISSな経路へ戻した。
- r3：資料を先に3段階へ更新。境界・入力／貼付け・保存／上書き拒否・dirty・undo・選択・コピー・スクロール・開き直しをテストへ追加。
- r3：最初の絞込ビルドは非公開のEditorPanelError参照で失敗。テストで正確なエラーを検査できる内部型へ変更。次のビルドはコンパイル中の性能テスト編集で中断し、ソース固定後に再実行。
- r3：変更パネルでdidSetからdraftを戻す処理がObservation経由で再帰しsignal 11。代入前に拒否するcomputed propertyへ修正。再実行は41テスト中コピーの3条件・6アサーションだけ失敗し、他の検査は成功。
- r3：コピー検査がサポート外のペーストボード形式を指定していた。AppKitヘッダーの手順に従いwritablePasteboardTypesへ修正し、同じコピー文字列一致・入力拒否等の3条件が成功（1テスト、失敗0）。
- r2：最終Releaseの4テスト成功。入力→描画p95は1 MB33.9 ms・2 MB41.2 ms・5 MB82.1 ms・実550 KB32.0 ms、他4文書は読込拒否。色付け13条件・文字形4条件も成功。撮影2テスト成功、8画像を直後にコピーして目視確認。保護対象44ファイルの内容一致とgit diff --checkを確認した。
- r2：本文をそのまま保持した最初の予備測定は1 MB346.6 ms・2 MB742.4 msで悪化。sampleでSwiftUIのビュー構造の正規化比較を確認し、今回のテスト子プロセスだけを停止した（成功扱いにしない）。
- r2：AnyViewのみは1 MB136.2 ms、クロージャのみは269.5 msで未達。両診断は今回の子プロセスだけを停止し、Bindingの参照型保持へ変更した。
- r2：参照型だけの診断は1 MB38.9 ms・5 MB114.4 ms・10 MB212.1 ms・20 MB411.8 ms・実HTML1,016.3 ms。帯のサイズ判定の繰返しを追加で修正した。
- r2：帯の判定共有後の20 MB上限での診断は2テスト成功。入力→描画p95は1 MB32.4 ms・2 MB40.1 ms・5 MB80.9 ms・10 MB149.8 ms・20 MB288.3 ms・実550 KB30.2 ms・実6.6 MB991.6 ms。50 MBは拒否。生データは `.build/large-file-performance/document-r2-cached.json`。
- r2：行番号変異の最初の絞り込みはsignal 5。AppKit初期化を補っても同じで、診断出力で複数行追加後の画像比較まで進んだと確認した。LLDBはOSのアタッチ拒否、直接起動は実行権限／Testing.framework不足で停止し、検査成功とは扱わない。
- r2：合成長行の最初の文字形変異は検査が通ってしまったため、提供された実HTMLと中央への移動・描画で強化し、4条件の失敗を確認した。古い検査のログは `.build/r2-mutation-glyph-ineffective.log` に保持。
- r2：5種類の変異を復元し、4ソースの退避時との一致・同じ4機能テストの成功を確認した。
- r2：最終コードの正本の全数はSwift Testing 4,097件・XCTest 6件成功（既存Release限定1件は対象外）。Debug buildと指定/tmpのUI build-for-testingも成功。
- r2：Release検査の事前 `swift build --build-tests` は `module 'DashboardFeature' was not compiled for testing` で失敗。指定されたswift test -c releaseで最終の性能検査を実行する。ログは `.build/r2-release-test-build.log`。
- r1（過去の記録）：非連続レイアウトだけの最終比較34条件はテスト完走したが、実HTMLのplain中央入力9,033.7msは悪化のため完了扱いにしない。結果は `.build/large-file-performance/final-noncontiguous.json` に保持。実FileTabViewは7条件時点で今回の子プロセスだけをSIGINTで止め、`.build/large-file-performance/document-data-interrupted.json` に保持した。
- r1（過去の記録）：AppKit切分けの初回は独立したNSTextViewのundo manager未設定でSIGTRAP（exit 133）。本番と同じ独立undo managerを用意した再実行は、3条件各6入力・undoのバイト一致確認で成功。glyphだけの追加比較も6入力・undoで成功した。ログは `.build/large-line-layout-benchmark-retry.log` と `.build/large-line-glyph-benchmark.log`。この比較を記録してからglyph準備を実装し、全数・性能・写真・両ビルドを最終コードで再検証する。
- r1（過去の記録）：文字形準備を加える前の版の全数テストはSwift Testingサマリー合計4,091件・XCTest6件成功、失敗0。色付け性能は2件成功・13条件達成。Debug build・UI build-for-testing成功。撮影2件成功で6画像を撮影直後に専用フォルダへコピーし、全6枚を目視確認した。文字形準備を含む最終版は再検証する。
- r1（過去の記録）：ProfilerのSwiftUI分類に性能テスト名 `measureDocumentAndSwiftUIUpdates` が混ざっていたため、そのフレームを除いて再集計した。原因特定の初回はSwiftUI86.1%（93.6%から訂正）、本文連続化後の実HTMLはTextKit98.1%・SwiftUI0.6%。測定値やtraceは保持する。
- r1（過去の記録）：`makeContiguousUTF8` 版の実FileTabViewは7条件まで測定後、実HTMLのTextKit組版が98.1%と特定できた時点で今回の子プロセスだけをSIGINTで止めた。成功とは扱わず `.build/large-file-performance/document-native-make.json` へ結果を保存。Data経由の最終版は別に全条件を実行する。
- r1（過去の記録）：既定の正本 `bash macos/scripts/run-swift-tests.sh` は6パッケージ・実git別パスとも成功。Swift Testingのサマリー合計4,090件、XCTestは6件成功・既存のRelease限定スクロール測定1件は通常実行では対象外。Swift Testingの環境依存17件も通常実行では対象外で、今回の性能測定は別コマンドで行う。
- r1（過去の記録）：例外修正後の通常回帰は35テスト成功（12.889秒）。実FileTabViewの非連続レイアウト、色付け、見出しのフォントバッチ、IME・undoを含む。Debug buildとUI build-for-testingは成功し、実アプリ起動・XCUITestは行っていない。
- r1（過去の記録）：修正前40条件は1テスト成功（4,012.653秒）。上限・保存の回帰42テスト、追加のIME・行番号回帰11テストも成功した。
- r1（過去の記録）：実ファイルタブの初回性能測定はAppKit例外 `attempted glyph generation while textStorage is editing`（signal 6）で失敗した。非連続レイアウトで発生する原因を直し、同じファイルタブを使う通常回帰を追加した。例外を握りつぶさず再検証する。
- r1（過去の記録）：計測手順と書き込み先の判断を実装前に記録した。
- r1（過去の記録）：初回の計測ビルドは合成長行のサイズ計算をビルド中に修正したため失敗（`input file ... was modified during the build`）。ソースを固定して再実行する。既存の非推奨API・actor隔離・不要なtry等の警告はログに保持する。
- r1（過去の記録）：1〜20 MBの正式計測とTime Profilerの値を根拠に、仕様・architecture・ADR0181を実装前に更新した。修正前の全条件計測は変更前にビルド済みの同じバイナリで継続する。
- r1（過去の記録）：RSS差分の負値は前条件の解放・再利用を含む。後半は対象プロセスだけのRSSを別ファイルで記録し、割当量として断定しない。Profiler集計はスタック欠測行で一度停止したため、欠測3msを明示して再集計した。
