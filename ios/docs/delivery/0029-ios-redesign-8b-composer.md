# iOS再設計 段階8b composer

## 計画と範囲

- セッション: ios-redesign-composer、基点 0c21a964。自worktree内のみ変更し、コミット・マージ・pushはしない。
- 新規チャット、DSInputBarと下位、モデル選択、使用量リングと詳細を担当する。共有GlassSurface/IOSColor、SessionDetailView/VM、撮影テストは変更しない。
- C1〜C11、比較obs.mdのDraft/Usage/Reply入力欄を、一次コード・HTML・8a画像で再判定する。Mac準拠のモデル種類・権限・usage計算は維持する。
- 小画面とDynamic Typeの到達性、寸法、状態表示を修正する。撮影専用差はfixtures担当への引継ぎにまとめる。
- ビルド・テスト・撮影は専任検証担当が統合後に実施する。本担当はコード確認とgit diff --checkを実施する。

## 品質設定

- ios/Makefile: generate/build/test/lint/snapshot。project.yml: iOS 18、Swift 6、Snapshotはunit-test bundle（XCUITestは実行禁止）。
- ios/scripts/lint-raw-values.sh: 色・書体の生値禁止。既存トークンを使う。
- .github/workflowsはpages.ymlのみ。今回の変更に対するiOS CIゲートは見当たらない。

## 結果

編集とコード確認を実施。生値lintとgit diff --checkはexit 0。ビルド・型チェック・テスト・変更後の描画・操作は未実施で、統合後の専任検証担当へ引継ぐ。追加した回帰テストも未実行。

### 比較と対応

ソースパスは `ios/Packages/PhloxKit/Sources/` からの相対表記。行番号は本作業終了時点。

| 指摘 | 判定・対応 | 一次根拠 |
|---|---|---|
| C1 | プロジェクトだけ44ptの背景だった。34ptへ統一し、縮みを防ぐ。新規チャットの幅計算から26ptの水増しを除去。通常34ptの見た目に44ptの押下領域を設ける | DesignSystemIOS/Molecules/DSInputBar.swift:386,1078,1156。Draft.dc.html:283〜284 |
| C2 | ＋の横圧縮を防止。空送信の全体opacityを除去。作成中スピナーを灰色へ変更。停止色は既存IOSColor.stopへ変更、四角の書体サイズを縮小。本文・操作列の最小高を見本へ合わせ、フォーカス時の枠を追加 | DSInputBar.swift:445,458,1156,1199,1224。DSFont+IOS.swift:37 |
| C3 | 選択済みプロジェクトを濃色にし、アイコンだけの表示でも⌄を残す | DSInputBar.swift:1078 |
| C4 | 提案の通常書体をsubheadline、背景高40pt、左余白16ptへ。横スクロールを画面端まで広げる | Features/NewChat/NewChatView.swift:179。Draft.dc.html:54〜58 |
| C5 | リングが18ptの外へ線幅分はみ出していた。線を枠内へ収め、ロゴ15pt・グループ間隔を縮小。拡大時の枠ラベルを22ptへ揃え、1段→2段→3段の折返しと上下余白を用意 | Features/Usage/UsageRingRow.swift:88,159。DSFont+IOS.swift:63。Reply.dc.html:550〜551 |
| C6 | Dot書体の指定値44ptが.custom(size:)により再拡大されていた。fixedSizeに変更。2行の見出しを保持し、小画面で新規画面を縦スクロール可能に。拡大時は＋・モデル・…・フォルダを先に配置し、送信を次段にする。長いモデル・強い権限は折返し側で横スクロール可能 | DSFont+IOS.swift:44。NewChatView.swift:30,98。DSInputBar.swift:755 |
| C7 | 作成中の発言を右寄せ・複数行・灰文字へ。進捗カードを白い背景、14/12ptの余白、15ptの補助書体に。スピナーはC2で修正 | NewChatView.swift:112,133 |
| C8 | 新規の入力検証行と作成失敗見出しを13pt semibold、左24ptへ。技術詳細に全角括弧。DSInputBarの添付・設定エラーをプロジェクト行の後ろへ。8aの詳しいエラー説明は維持 | NewChatView.swift:276,287。DSInputBar.swift:430,545 |
| C9 | 新規シートの余分なpadding/clip/material重ね合わせを除去。新規・返信でモデル選択の枠を共用し、閉じるを固定字幅のカプセル、白い一覧、説明を一覧直後へ。チェックの列を常時確保し既定札の横位置を揃える | NewChatView.swift:73,325。Features/SessionDetail/ModelPickerSheet.swift:18。ModelSelectionSheet.swift:5 |
| C10 | 使用量詳細の数値をsemiboldへ。矢印の起点を先頭ロゴの矩形へ。拡大時の詳細は縦積み・スクロールで読めるようにする。「…」の撮影用吹き出しは下記の担当外 | UsageRingRow.swift:70,186,257 |
| C11 | 使用量のコマンド・メトリクスは撮影用ホストの責務。入力欄担当では変更しない | ios/PhloxMobileSnapshotTests/DesignSnapshotRenderTests.swift:509付近。fixtures/cards担当へ |

C9の8a画像は存在しない。0028:104〜109でモデル・権限・プロジェクトの選択面を撮影対象外としているため、縦じま・透け・OS18の浮いた外形を本担当が実画像で再現確認したとは扱わない。重ね合わせの除去と共通レイアウトはコード上の対策であり、改善の成否は未検証。OS標準シートの外縁そのものを独自実装へ置き換えてはいない。

### 画像で確認した範囲

- 見本と8aの両方: Draft、DraftDT、DraftCreating、UsagePop、ReplyRunText（428pt/light/iOS26）。
- 追加の8a: DraftSE（375pt/light/iOS26）、DraftMoreDT、UsagePopDT（428pt/ax5/iOS26）。DraftModelは見本のみ。その他の盤面・OS18・darkは一次コードと既存比較を参照しただけで、画像の全数確認はしていない。
- 停止色は画像の赤系画素も集計した。見本ReplyRunTextの最多色はRGB(214,47,38)＝#D62F26、8aの最多色は(169,51,38)。Draft.dc.html:259とReply.dc.html:383はstop=#D62F26、darkは#E5483F。IOSColor.swift:11の既存stopトークンが一致し、errorトークンとは別物である。変更後の画素は未確認。
- 差分の比較記録: 自worktreeの `.verification/ios-redesign-stage8b/compare/composer.md`。共有obs.mdは他担当worktreeのため編集しない。

### 維持したMac準拠の差

- 提案文はmacos/Packages/DashboardFeature/Sources/DashboardFeature/NewChat/NewChatView.swift:958と現在のNewChatViewModel.swift:131が一致。DraftSuggest見本に合わせて提案の実文面を戻さない。
- モデル種類・既定選択・権限名・モデル検索条件・usageの計算は変更しない。残り率はMac UsageDisplay.swift:93とiOS UsageRingPresentation.swiftの100−使用率を維持する。
- 作成失敗の説明は段階8aのErrorPresentationを維持し、見本の短文へ戻さない。

### 他担当への要求（編集せず引継ぎ）

- list: `DesignSystemIOS/Support/GlassSurface.swift:38〜41`のiOS18 inputFieldに常時1pt枠が残る。C2の非フォーカス枠の差は共有面で判断が必要。共通色の追加要求はない。停止色は既存stopで解決する。
- fixtures: `ios/PhloxMobileSnapshotTests/DesignSnapshotRenderTests.swift:2002〜2008`はMoreパネルを画面中央x・高さ0.58へ置く。入力欄の右端・上8ptへ揃えるのは撮影側の修正。`:2050〜2069`の行高51ptに対しDSFont.bodyがax5で拡大するため、枠からはみ出す（NEW-3）。本物のDSInputBarはOS標準Menuであり、この固定高の独自パネルを使用しない。
- fixtures: Reply*/Usage*は`:509`付近の専用組立を本物のSessionDetailViewへ揃える必要がある（A1/C11）。UsagePopDTの詳細にもDynamic Typeが届く撮影を確認する。モデル・権限・プロジェクトのシートは8a画像が無く、描画確認を新たに必要とする。
- fixtures: DraftSuggestの文面を見本へ変更する要求（A2）はMac準拠により採用しない。UsageLow/Naのどの枠を低残量・取得不可にするかはfixtureの値の問題であり、計算規則を変えない。
- cards/chat: 承認・質問・送信失敗など、DSInputBar外のC8のエラー行は本担当で編集していない。`SessionDetailView.swift:634`のモデルシートは高さ680のみを指定したまま（所有外）。拡大時に.largeも選べるようにするか、統合担当で確認する。

### 検証

- git diff --check: exit 0。
- bash ios/scripts/lint-raw-values.sh: exit 0、色・書体の生値検出なし。
- Swiftの整形ツールによる編集時の構文処理: 成功。コンパイラーによる型チェックの代わりではない。
- 既存のDSInputBarLayoutTestsへ、375/428pt相当の拡大新規画面、長いモデル名と強い権限を残す回帰検査を追加（未実行）。
- lint以外の静的解析、ビルド／リンク、単体テスト、統合／描画テスト、実機／シミュレーター操作: 専任検証担当へ引継ぎのため未実施。とくにシート・popoverの高さ、キーボード併用、横スクロール時の押下領域、OS18/darkを要確認。
- XCUITest、.env操作、共有ファイルの変更、コミット・マージ・pushは行っていない。検証プロセスの起動なし。

### 変更ファイル

- `ios/Packages/PhloxKit/Sources/DesignSystemIOS/Molecules/DSInputBar.swift`
- `ios/Packages/PhloxKit/Sources/DesignSystemIOS/Tokens/DSFont+IOS.swift`
- `ios/Packages/PhloxKit/Sources/Features/NewChat/NewChatView.swift`
- `ios/Packages/PhloxKit/Sources/Features/SessionDetail/ModelPickerSheet.swift`
- `ios/Packages/PhloxKit/Sources/Features/SessionDetail/ModelSelectionSheet.swift`（新規）
- `ios/Packages/PhloxKit/Sources/Features/Usage/UsageRingRow.swift`
- `ios/Packages/PhloxKit/Tests/DesignSystemIOSTests/DSInputBarLayoutTests.swift`
- 本作業記録（新規）。比較補足と所有記録はGit除外済みの自worktree `.verification/ios-redesign-stage8b/` 内。
