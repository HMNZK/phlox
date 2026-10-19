---
status: active
---

# 最大文字サイズと送信失敗の描画経路を揃える

## 実装前の確認

- `DSThinkingIndicator` は状態と補足を横並びにし、補足を1行で省略している。アクセシビリティ用文字サイズでは補足を次行へ送り、本文を折り返して読めるようにする。
- 製品の `UsageRingPopover` はアクセシビリティ用文字サイズで列見出しを外し、各枠を縦配置にする分岐がある。撮影側はSwiftUI環境値のみを指定し、UIKitの撮影用ウィンドウには文字サイズを指定していない。まず撮影用ウィンドウのtraitを揃え、本物のpopoverが同じ文字サイズを受け取ることと、列見出しが消えることを検査する。製品側の変更は行わない。
- `ChatSendFail` は `SessionDetailRecovery.errorMessage` により1行の復元エラーを表示し、送信失敗の4段表示を作っていない。撮影APIで送信を失敗させ、公開の `sendMessage()` を通じて見出し・原因・次の行動・技術行を作る。

## 変更と検証の範囲

所有する製品部品と描画テストのみを変更する。通常のUI設定・Simulator設定・入力ソースは変更しない。設定済の入口は `ios/Makefile` のlint・SwiftPMテスト・ビルド・snapshotと `ios/project.yml` のsnapshot scheme。テストとビルドは統合後の検証担当が実行するため、実装担当は実走しない。

## 実装した差分

- 思考中の補足はアクセシビリティ用文字サイズで縦積み・行数制限なしとし、読み上げにも補足を含めた。回帰テストは最大文字サイズ・幅320で状態と補足の必要な高さを測り、両方を縦に収める高さが確保されることを検査する。
- input/usage描画の文字サイズを撮影用 `UIWindow.traitOverrides` にも設定した。本物のpopoverを開き、UIKit側の文字サイズの一致と、通常サイズの列見出しの存在・アクセシビリティ用サイズでの不在を検査する。これはfixtureの環境の修正であり、実行後の伝播結果と画像は未確認。
- `ChatSendFail` とその派生場面は、撮影APIの `.unreachable` を公開の `sendMessage()` に返し、`sendErrorPresentation` ができたモデルで描画する。見本の技術行の例文を製品へ注入せず、現在の製品が返す「Mac から応答がありません」を使う。回帰テストは4段の内容と本文・添付の保持を検査する。
- `PairConnectFail` の案内は、採用記録 `0029-ios-redesign-8b-pair.md` の「既存NEW-32差は採用済みPair盤面のチェックリストを維持する。Errors C1の1文案内への一本化は別途判断」に従い、seedの3項目を維持した。当初の親指示で1文へ変更した差分だけを復元し、今回の成果から外した。主・隔離の `AppRoot.swift` は変更していない。

Usageの列見出し不在検査より先に、本物のpopoverの存在、native文字サイズの一致、サービス名「Claude Code」のAX要素の存在を必須検査する。独立レビューで従来の探索が通常のUIViewラベルでも成功する問題を確認したため、popoverのviewを起点に公開AXコンテナの子だけを辿る専用探索へ変更した。非AXのUIViewはラベル一致だけでは採用せず、AXコンテナ由来のプロキシは扱う。空ツリー、非AXラベル、公開AXプロキシを区別する回帰テストを追加した。AXツリーを取得できない場合はサービス名の検査で失敗し、列見出し不在だけで成功にはならない。この到達性自体は実走前のため未確認。

実装担当の確認は差分の読み直しと `git diff --check` の指摘なしまで。テスト・ビルド・lint・描画は未実行で、成功を主張しない。

統合後のコンパイルで、高さ検査の `.environment(\.accessibilityReduceMotion, true)` は読み取り専用キーのためエラーとなった。高さ検査は動きの抑制を受け入れ条件としていないため、この書込みだけを除去した。最大文字サイズで状態と補足の全文を収める必要高さの検査は維持し、OS設定は変更しない。修正後のビルドとテストは親の再検証待ち。

## probe26の失敗と追加契約

`accessibility-motion-usagepopdt26.log` は9テスト中7成功・2失敗、exit 65、PNG 0。実popoverとnative文字サイズの一致は通過したが、アプリ内の公開AXツリーからサービス名を取得できなかった。検査を削除せず、外部CUAが実popover表示後に取得するfresh AX原文をnonce・scene・pid・udid・専用Simulatorウィンドウ名・取得時刻つきJSONで受け渡す。3サービスが個別のAX名として存在することを必須とし、native AX5一致、通常列見出しの不在を順に検査する。空・別画面・別実行・期限外の証拠は失敗させ、parserの人工fixtureは実測証拠と区別する。具体的なnative AX構造は最初の外部取得結果と照合して確定する。

高さ検査の `previewHeight > labelHeight` は、補足の `DSFont.caption` が共有 `Tokens.swift:27` の固定11pt、状態が拡大される `.footnote` だったため異なる書体の高さを比較していた。一方、固定11ptの補足自体もAC-2-7のDynamic Type追従に不適合だった。補足だけ既存iOSの `iosCaption2`（標準11pt・Dynamic Type追従）へ置換する。回帰テストはnative AX5・幅320・日本語locale・同じ全文と書体を使った基準VStackと実部品の高さを比較し、短い補足より必要高さが増えることも検査する。両者のどちらかが高いという任意の仮定は受け入れ条件にしない。

今回の製品変更は思考中補足の書体だけとし、他のcaptionへ広げない。テスト実行・コンパイルは親へ事前連絡し、compact-test経由の対象検証に限定する。OS/Simulator設定と入力ソースには触れない。

### 外部AX証拠の受け渡し

`PHLOX_SNAPSHOT_EXTERNAL_USAGE_ACTIVATION=1` では、従来どおり `<scene>-external-ready.json` の `awaitingTap` で親が実ボタンを押す。実popover表示とnative trait一致後に同ファイルの `phase` が `awaitingAXProof` になり、nonce・scene・pid・udid・windowTitle・requestedAt・nativeContentSizeCategory・proofFileを通知する。専用Simulatorウィンドウのタイトルが端末名と違う場合は `PHLOX_SNAPSHOT_EXTERNAL_AX_WINDOW_TITLE` で正しいタイトルを明示する。

親はその時点のCUAのfresh AX原文を取得し、`proofFile` の絶対パスへ次のJSONを原子的に保存する。nonce/scene/pid/udid/windowTitleはreadyの値をそのまま使う。`capturedAt` は取得時のUnix秒、`rawAXTree` は取得した原文であり、人工fixtureを使わない。

```json
{"nonce":"readyのnonce","scene":"readyのscene","phase":"presentedAX","pid":123,"udid":"readyのudid","windowTitle":"readyのwindowTitle","capturedAt":1792000000.0,"rawAXTree":"CUAが返した実際の原文"}
```

待機は60秒。成功時はreadyが `validatedAXProof`、失敗時は `failedAXProof` になり、証拠JSONは検証記録として保持する。初回probeではCUAの実際の要素名・階層・popover境界を確認し、parserの形式を実原文へ照合する。原文取得・このprotocolの実走はまだ行っていない。

### r2実測と測定ホストの後片付け

親の `accessibility-proof-probe26-r2.log` では10テスト成功・PNG 1。実AX原文は `snapshots/accessibility-proof-probe26-r2/UsagePopDT-41312B65-4D73-4331-89F7-C8C30E477CBB-external-ax.json` に保存され、実popover表示、nativeの最大文字サイズ、3サービスの個別AX名、通常列見出しの不在を通過した。原文には `PopoverDismissRegion` とその後の各サービス・枠の縦ラベルがある。Thinkingの高さは全文基準474・実部品474・短文185.67で成功した。

同runで `Unbalanced calls to begin/end appearance transitions` が3件残った。型名がThinking高さ計測の3つのhosting controllerと一致し、測定用UIWindowを表示して即座に隠しrootを外す経路で発生した。高さ計測には画面表示が不要なため、UIHostingController自体へnative AX5 traitを設定して画面外で同じ幅・全文をlayoutする構成にし、UIWindowの出現・退場を発生させない。nativeカテゴリと全文基準・短文差の検査は維持し、修正後の警告件数は再probe待ち。

親のPNG確認では、最大文字サイズの実popoverは縦スクロールでClaudeとCodex冒頭までが見えている。全文が同時に画面内へ収まるという検証ではない。末尾への実スクロール到達性は別のCUA操作で確認する。

### 実スクロール領域の診断と退避

親CUAのscroll/dragで表示が動かなかったが、画像のRetina座標と実ウィンドウの座標差もあり、製品不具合とは断定しない。実popover内に公開UIKitの `UIScrollView` があるかを別の診断として再帰探索し、実表示直後と外部AX証拠受領直後に `<scene>-scroll-presented.json` / `<scene>-scroll-proofReceived.json` を保存する。

各記録はnative文字サイズ、表示倍率、popover/スクロール領域のframe・bounds・window上のrect、内容サイズ、content inset・adjusted inset、content offset、scroll有効状態、祖先のclip状態を含む。Cursorの公開AXが取得できればframeを記録し、取得できなければ明示的に `unavailable` とする。UIKitのview探索を、AXの到達性検査と混同しない。

既存proof検査・高さ検査・待機時間は変更しない。初回は数値の期待値や回帰assertを追加せず、操作前後の実測からviewportの制約と内容超過の有無を確定する。診断追加前に成功した正式full26の画像・検証記録は保持し、追加後のtest artifactとは区別する。

初回 `usage-scroll-diagnostic26.log` は親の証拠JSON供給が60秒の期限内に完了せず、`Fresh external popover AX evidence was not provided` で10テスト中9成功・1失敗となった。検査の省略や待機時間延長は行っていない。再実行 `usage-scroll-diagnostic26-r2.log` は10テスト成功、fresh proofが `validatedAXProof` となった。

再実行の正規JSONでは、最大文字サイズのpopoverのwindow上rectは `[10,57,300,739]`、実 `SwiftUI.HostingScrollView` の表示領域は幅293.667・高さ739、内容は幅293.667・高さ1530.667、adjusted inset下13、スクロール有効だった。表示直後と証拠受領直後のoffsetはともに `[0,0]`。有限の表示領域があるため、「高さ制限がなく外側で切れる」という仮説は反証された。in-processのCursor AXは `unavailable`、外部の実AX原文には3サービスの独立した要素があった。

親はAX要素を対象としたwheelとdragを実送信したが、offsetは変わらなかった。入力の届き方・座標・gesture動作の原因は特定しておらず、製品不具合とは断定しない。末尾への実操作到達性は未検証として保持し、製品のUsageRingPopoverは変更していない。

今回だけの診断calls/helperを除去し、Snapshotを正式full26と同じSHA256 `31ad43561f76fb0e957f3bebd4bf36792f1e0c0c218d25118267c652137fae32` へ正確に戻した。既存AXproof・Thinking・他テストは保持している。診断ソース（SHA256 `70a4e5cf1cf147052d9ecf2a529f87bc0687a3946e9914bd2e1b768c4a11c6c9`）、復元後ソース、両者のpatch、hash manifest、初回失敗・再実行成功のログと正規JSONは `.verification/ios-redesign-stage8b/diagnostic-source-archive/usage-scroll/` に保存した。上位archiveには他の診断記録が既存のため、専用サブディレクトリへ分離した。今回の退避・復元作業でビルド・テスト・Simulator操作は実行していない。
