# 段階8b: list 担当

## 計画・所有範囲

- 基点: feature/ios-redesign-list（0c21a964）、着手時の未コミット変更なし。
- 所有: SessionList、AppShellView、下部タブ・セッション上部の共通部品、IOSColor/GlassSurface のサーフェス。
- A/B/F の指摘を現コード、ClaudeDesign の HTML、段階8a PNG と見本 PNG で確認し、採用済みの Mac 準拠・仕様決定を保持する。
- 撮影 fixtures、SessionDetailView、共通 0020/0028 は編集しない。ビルド・テスト・再撮影は統合後の専任検証担当へ引き継ぐ。
- 編集後は差分を読み直し git diff --check を実行する。コミット・マージ・push はしない。

## 検証環境

- 一時資料: 自 worktree `.verification/ios-redesign-stage8b/`。作成セッション: stage8b-list。
- 起動プロセス: なし。ビルド・シミュレーター・XCUITest は実行しない。
- 品質設定確認: ios/Makefile（generate/build/test/lint/snapshot）、ios/project.yml、ios/scripts/lint-raw-values.sh。現 worktree の .github/workflows は pages.yml のみ（iOS CI は未設定）。

## 調査・結果

以下の「修正」はコード編集済みの意味で、修正後の描画成功を意味しない。

| 指摘 | 判定・実施内容 | 一次根拠（パスは ios/ から） |
|---|---|---|
| A1/A3 | 範囲外。Reply/Usage の実画面ホスト・承認説明文は fixtures/cards 担当へ | PhloxMobileSnapshotTests/DesignSnapshotRenderTests.swift、Packages/PhloxKit/Sources/Features/SessionDetail/SessionDetailView.swift |
| A2 一覧の展開 | 差が残る。撮影側が listChildrenExpanded 以外で空の展開集合を渡している。fixtures 担当へ、List/ListMulti/ListAllAttention/ListCollapsed/ListSE/ListDT/ListManyTop の見本ごとに親 refactor の初期展開を指定する依頼 | PhloxMobileSnapshotTests/DesignSnapshotRenderTests.swift:277、docs/specs/ClaudeDesign/List.dc.html:346 |
| A2 件数・未読 | 対応待ち 4 状態・待ち時間順・未読は doneUnread の規則を維持。見本の running の太字等に合わせてドメイン判定を変えない | Packages/PhloxKit/Sources/Features/SessionList/SessionGrouping.swift:10、:279、macos/Packages/DesignSystem/Sources/DesignSystem/StatusBadge.swift |
| A2 Shell データ | Shell は Design polish / Snapshot updates / Release checklist の別データ。見本の Phlox/refactor 等との差は fixtures 担当へ。ListCollapsed の内訳も domain 規則を変更せずデータで扱う | App/AppEnvironment+UITesting.swift:119、docs/specs/ClaudeDesign/Shell.dc.html:19 |
| B1 ネット断 | 下部帯の固定「Mac に届きません」を到達状態別の既存 cardTitle に変更。ネット断にスリープ/Tailscale の補足を付けない。VoiceOver も同じ文言 | App/AppShellView.swift:190、Packages/PhloxKit/Sources/Features/SessionList/UnreachableViewModel.swift:28 |
| B1 接続先不明 | 反証（採用済み仕様差）。AC-3-5 は接続判定中の帯を出さない。unknown 時の非表示を維持 | docs/specs/redesign-2026-10.md:113、Packages/PhloxKit/Sources/Features/AppShell/SessionNavigationState.swift:72 |
| B1 Host の補足・操作色 | 反証（採用済み仕様差）。C-18 は専用 ShellOffline を正として「スリープ中か Tailscale 切断」＋淡色ボタンを採用。ListOffHost へ合わせ直さない | docs/specs/redesign-2026-10.md:395、docs/specs/ClaudeDesign/Shell.dc.html:110 |
| B2 | オフラインカードと骨組みを ZStack から縦積みに変更。カード下 26pt を確保。オフライン時は 2 行→4 行の 2 カードだけにし、通常読込は 3 カードを維持 | Packages/PhloxKit/Sources/Features/SessionList/SessionListView.swift:196、:394、docs/specs/ClaudeDesign/List.dc.html:415 |
| B3 | 通常名は 1 行、アクセシビリティ文字サイズの名は 3 行までで省略。光の帯のマスクも同じ制限。件数円の最小径を文字サイズに追従。iOS18 の新規作成記号は 44pt の操作領域内で通常サイズに保つ | Packages/PhloxKit/Sources/Features/SessionList/SessionListView.swift:14、:607、Support/DSPlatformTabView.swift:123 |
| B3 帯 | 帯のタイトル・副題は accessibility1 まで拡大（AX5 で約26/23pt）。「開く」と再接続の字は見本どおり通常サイズのまま、横幅を確保して 34/40pt の面から溢れないようにする | App/AppShellView.swift:139、:148、:207、docs/specs/ClaudeDesign/List.dc.html:266、:184 |
| B4 | 通常名の 1 行省略を修正。SE/iOS18 のタブラベル欠けは未解決。撮影ホストは 375x667 をホームインジケータ付き端末のウィンドウへ載せ、bottom safe area を 0 へ上書きしている。ネイティブ TabView 内部と切り分けが必要。fixtures 担当へ引継ぎ（原因確定ではない） | PhloxMobileSnapshotTests/DesignSnapshotRenderTests.swift:321、:1554、Packages/PhloxKit/Sources/DesignSystemIOS/Support/DSPlatformTabView.swift:61 |
| B5 余白 | iOS26 の下部帯の二重横余白 16pt と余分な縦余白 8pt を除去。iOS18 は素材を外側の余白より先に適用し、左右12ptの範囲だけを塗る。帯内部は左18pt・右10pt | Packages/PhloxKit/Sources/DesignSystemIOS/Support/DSPlatformTabView.swift:30、:92、App/AppShellView.swift:155 |
| B5 不透明白・影 | 反証（採用済み仕様差）。AC-2.6 は iOS26=ガラス、iOS18=素材。白い不透明面・独自の影への置換はしない | docs/specs/redesign-2026-10.md:97、Packages/PhloxKit/Sources/DesignSystemIOS/Support/GlassSurface.swift:39 |
| B6/B7 | 未修正・判断待ち。帯なし時の短いタブ幅、記号寸法、タブ全体の下寄りは段階8a PNG に残る。標準 TabView の配置で、幅や位置を固定するコードはない。標準タブ採用を崩す独自バーや OS 内部ビュー操作は入れない。専任検証担当は実ウィンドウで再確認が必要 | Packages/PhloxKit/Sources/DesignSystemIOS/Support/DSPlatformTabView.swift:48、App/AppShellView.swift:108、docs/specs/redesign-2026-10.md:91 |
| B8 | 対応待ちセクションの上余白を 4→16pt（12pt 下） | Packages/PhloxKit/Sources/Features/SessionList/SessionListView.swift:708 |
| B9 | エラー・到達不可の本文に行間5ptを追加。接続判定の上余白144→140pt、要素間16→12pt。本文トークンは元から subheadline=15pt、見出しも title3=20pt で見本の値と一致。spinner は標準 large を維持（HTML 32pt、過去記録の28ptは正本と不一致） | Packages/PhloxKit/Sources/Features/SessionList/SessionListView.swift:177、:661、:715、UnreachableView.swift:20、docs/specs/ClaudeDesign/List.dc.html:48 |
| B10 | 反証。status.error は元からライト #B8241C／ダーク #FF8C82 で List の c.errFg と一致。IOSColor は変更しない | Packages/PhloxKit/Sources/PhloxCore/Shared/SessionGlanceState.swift:44、docs/specs/ClaudeDesign/List.dc.html:256 |
| F1 | 未修正・判断待ち。詳細上部は見本の navRow=52pt に対し OS 標準 UINavigationBar。段階8a の線・中央タイトル位置の差を画像で確認。独自オフセットではバー内部と本文の境界を揃えられず、標準ナビ採用との設計判断が必要。SessionDetailView は変更なし | Packages/PhloxKit/Sources/DesignSystemIOS/Support/DSSessionNavigationChrome.swift:29、docs/specs/ClaudeDesign/Detail.dc.html:590 |
| 共通 card 下地 | iOS26 の glassSurface(.card) に既存 bg.card の下地を追加し、ライト/ダークで画面色へ透けすぎないようにした。角丸・iOS18の枠・入力欄のsurfaceは維持 | Packages/PhloxKit/Sources/DesignSystemIOS/Support/GlassSurface.swift:22、docs/specs/ClaudeDesign/Detail.dc.html:526 |

### cards 担当・検証担当への引継ぎ

- `SessionDetailView.swift` は未変更。Detail/Detail18/DetailDT/DetailDark/DetailSE/ListTapDetail の上部を確認した。名前・状態・メニューは存在する。F1 の 52pt 見本と標準バーの差、DetailDT の承認カードが上の会話へ重なる状態は今回直していない。
- `GlassSurface.swift:22` の共通下地は承認・質問カードへ波及する。統合後、ReplyApprovalDark/ReplyQuestionDark/DetailDark とライト版を両 OS で再描画して確認する。
- 新規回帰テスト・撮影テストは追加していない。今回の変更は表示配置で、既存の `DesignSnapshotRenderTests` の ListDT/ListSE/ListOff* と ShellDT/ShellSE を統合後に実走する。既存の UnreachableViewModelTests と SessionNavigationStateTests も維持する。
- A1/A3 の fixture・承認処理、B4 の撮影ホスト、B6/B7/F1 の標準 chrome の差は解消済みと扱わない。

## 検証結果・変更ファイル

- `compact-test ios-stage8b-list-lint bash ios/scripts/lint-raw-values.sh`: exit 0、`OK（要約未対応）`。
- `git diff --check`: exit 0。
- 変更ソース: `App/AppShellView.swift`、`Packages/PhloxKit/Sources/DesignSystemIOS/Support/DSPlatformTabView.swift`、`GlassSurface.swift`、`Packages/PhloxKit/Sources/Features/SessionList/SessionListView.swift`、`UnreachableView.swift`。本作業記録と合わせて6ファイル。
- 未実行: ビルド・リンク、単体テスト、統合テスト、シミュレーター起動、変更後の PNG 撮影、実機操作。専任検証担当に委任するという今回の指示に従う。独立した型チェック/静的解析ゲートは ios/Makefile に未設定。
- コミット・マージ・push なし。常駐プロセスなし。`.verification/ios-redesign-stage8b/` の縮小比較資料は統合時の再分析用に保持する（変更後の画面ではない）。

## 担当盤面の確認一覧

「確認済み」は見本 PNG と**段階8a** PNG の読み取り。変更後は以下の盤面いずれも未確認。HTML の親 List/Shell/Detail と各ラッパーの import 指定を確認した。Detail は上部だけが担当。OS 標準書体の微差と Mac 決定済みの表示差は修正対象から除いた。

| 盤面 | 既存画像の確認範囲 | 変更後 |
|---|---|---|
| List | 見本・iOS18/26、light/dark | 未確認 |
| ListAllAttention | 見本・iOS18/26 | 未確認 |
| ListCollapsed | 見本・iOS18/26 | 未確認 |
| ListDT | 見本・iOS18/26 AX5（原寸も確認） | 未確認 |
| ListDark | 見本・iOS18/26 dark | 未確認 |
| ListEmpty | 見本・iOS18/26 light/dark | 未確認 |
| ListEmptyDark | 見本・iOS18/26 dark | 未確認 |
| ListError | 見本・iOS18/26 | 未確認 |
| ListError401 | 見本・iOS18/26 | 未確認 |
| ListJudging | 見本・iOS18/26 | 未確認 |
| ListLoading | 見本・iOS18/26 light/dark | 未確認 |
| ListLoadingDark | 見本・iOS18/26 dark | 未確認 |
| ListManyScrolled | 見本・iOS18/26 | 未確認 |
| ListManyTop | 見本・iOS18/26 | 未確認 |
| ListMulti | 見本・iOS18/26 light/dark | 未確認 |
| ListMultiDark | 見本・iOS18/26 dark | 未確認 |
| ListOffHost | 見本・iOS18/26 light/dark（light26は原寸も確認） | 未確認 |
| ListOffHostDark | 見本・iOS18/26 dark | 未確認 |
| ListOffNet | 見本・iOS18/26 | 未確認 |
| ListOffUnknown | 見本・iOS18/26 | 未確認 |
| ListPressed | 見本のみ。対応する8a PNGなし | 未確認 |
| ListPull | 見本のみ。対応する8a PNGなし | 未確認 |
| ListSE | 見本・iOS18/26 light/dark | 未確認 |
| ListSEDark | 見本・iOS18/26 dark | 未確認 |
| ListSpec | 説明資料。アプリ画像の対象外 | 対象外 |
| ListTapDetail | 見本・iOS18/26、上部のみ | 未確認 |
| Shell | 見本・iOS18/26 | 未確認 |
| Shell18 | 見本・iOS18 | 未確認 |
| ShellDT | 見本・iOS18/26 AX5 | 未確認 |
| ShellDark | 見本・iOS18/26 dark | 未確認 |
| ShellOffline | 見本・iOS18/26、帯のみ | 未確認 |
| ShellSE | 見本・iOS18/26 | 未確認 |
| ShellThumb | 見本のみ。到達範囲の説明盤面、対応する8a PNGなし | 未確認 |
| Detail | 見本・iOS26、上部のみ | 未確認 |
| Detail18 | 見本・iOS18、上部のみ（原寸も確認） | 未確認 |
| DetailDT | 見本・iOS18/26 AX5、上部のみ | 未確認 |
| DetailDark | 見本・iOS18/26 dark、上部のみ | 未確認 |
| DetailSE | 見本・iOS18/26、上部のみ | 未確認 |
| DetailThumb | 見本のみ。到達範囲の説明盤面、対応する8a PNGなし | 未確認 |

追加の8a盤面 ShellNoAttention/ShellDetail/ShellScrolled は今回の縮小比較対象に含めていない（未確認）。統合後のタブ・上部確認ではこれらも対象にする。
