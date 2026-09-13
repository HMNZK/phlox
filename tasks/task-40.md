---
id: task-40
difficulty: standard
depends_on: []
user_visible: true
acceptance_tests:
  - macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceTranscriptTypographyTests.swift
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptTypographyIntegrationTests.swift
  - .claude/scripts/task40-wiring.rb
baseline_commit: 4285918
contract_tests: []
allowed_paths:
  - macos/Packages/DesignSystem/Sources/DesignSystem/TranscriptTypography.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatTypography.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatScaledFont.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatTranscriptGrouping.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatTranscriptView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Basic.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCellsCommon.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Structured.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+CommandGroup.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+TaskList.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/RichMarkdownView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatCodeBlock.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatCodeCard.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/CompactingIndicatorCell.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/UserQuestionCell.swift
  - docs/agent-output/task-40.md
---

## 目的

UI-03 / P1「本文・処理見出し・補助情報の文字と余白を整理する」。システムフォントと既存の文字倍率設定を維持し、本文・節見出し・処理の要約・時刻の役割をそろえる。同じ回答内、回答本文への切替、新しいユーザー入力の区切りを、既存の8／16／24ptトークンで区別する。

仕様は `macos/docs/specs/ui-ux-improvement-backlog.md:158`。巨大な文字や大きなカードへの置換、新規ライブラリ、チャット機能の変更は行わない。

本契約は Codex 草案 `docs/agent-output/contract-draft-task-40.md` を PM が 2026-09-13 に採択したもの。原文:製品コード・テスト・検査スクリプトを変更せず、テスト、ビルド、GUI検証も実行していない。

調査開始時のHEADは `3921d9c77f4a2fe1290771689beb2cfc9b513d03`、終了時は `bb8006cefd64d9dac21c1c19eaf148145b2db5e5`。その間の変更は task-34 の契約・状態と決定ログで、以下の調査対象製品コードに変更はなかった。いずれも本タスクの凍結基準には自動採用しない。

## 入出力契約

### 担当と凍結条件

- 実装担当は Cursor。受け入れテスト、Ruby検査、検証用フィクスチャはPMが作成し、Cursorは作成・変更しない。
- 独立レビューは実装担当と別モデルが行う。
- PMは本契約の期待値からテストと検査を作成し、未実装を原因とするREDと、検査自身の `--selftest` 成功を確認して凍結する。
- `acceptance_tests` のSwiftファイルはSwiftPMパッケージ内のSwift Testingとする。`macos/App` にテストを置かない。
- テスト、Ruby検査、`tasks/task-40.md`、検証スクリプト、台帳、PM目視記録は `allowed_paths` 外であり、PM所有とする。
- `TranscriptTypography` と後述する新しい公開面は本契約で提案する名前であり、調査時に存在したシンボルではない。

### 現状の描画経路

以下のパスの省略表記 `SF/` は `macos/Packages/SessionFeature/Sources/SessionFeature/`、`DS/` は `macos/Packages/DesignSystem/Sources/DesignSystem/` を指す。

- `SF/ChatSessionView.swift:117` の `mainColumn(width:)` が `ChatTranscriptView` と浮遊する `ChatComposer` を配置する。入力欄の高さはスクロール内容末尾の余白へ渡される。
- `SF/ChatTranscriptView.swift:148` の `transcriptStack` が既存のブロック分類・表示件数制限を使い、`ChatItemView` または `CommandGroupCell` へ接続する。
- `SF/ChatMessageCells.swift` の `ChatItemView` がユーザー本文、回答、処理、差分、エラー、質問等を各セルへ振り分ける。
- `SF/ChatMessageCells+Basic.swift:184` の `AgentMessageBody` はMarkdownとコードを分け、`RichMarkdownView` と `CodeBlockView` を描く。`RichMarkdownView` 内にもコードブロック描画経路があるため、両方を対象にする。
- `SF/ChatMessageCellsCommon.swift:46` の `DisclosureCard` が処理グループ、Reasoning、差分、タスク等の共通見出しを担う。

### 現状の文字・色・余白

数値は倍率1.0でのソース上の指定値。`DSFont` の意味的フォントについてOSでの実寸は今回未計測であり、数値指定と区別する。

| 役割・実ファイル | フォント・太さ | 色 | 間隔・余白 |
|---|---|---|---|
| 共通トークン：`DS/Tokens.swift:5`、`:21` | `body = Font.body`、`caption = Font.caption`、`captionStrong` はmedium、`sectionHeader` はsubheadline／semibold。macOS用 `bodyPointSize` は13 | 各Viewで選択 | `xxs=2`、`xs=4`、`s=8`、`m=12`、`l=16`、`xl=24`、`xxl=32` |
| Markdown本文：`SF/RichMarkdownView.swift:49` | `ChatTypography.bodyFontSize`＝15×倍率 | `chatTextPrimary` | 段落・箇条書きには高さ確保を指定。独自の段落間隔は未指定 |
| Markdown節見出し：同ファイル`:81` | H1＝26／bold、H2＝19／bold、H3＝16／semibold。H4〜6の独自サイズ・太さは未指定 | H1〜3は `chatTextPrimary` | 上／下：H1＝0／12、H2＝8／8、H3＝8／4。H4〜6は独自間隔未指定 |
| ユーザー本文：`SF/ChatMessageCells+Basic.swift:48` | `ChatScaledFont.body`＝13×倍率、regular | `chatTextPrimary` | 行間3。本文・添付等の縦Stackは4。吹き出し内は水平12／垂直8 |
| 回答内のMarkdown・コード間：同ファイル`:184` | 各子Viewへ委譲 | 各子Viewへ委譲 | `AgentMessageBody` のStackは12 |
| 共通処理見出し：`SF/ChatMessageCellsCommon.swift:83` | タイトル10×倍率／medium、補足10×倍率／regular | ツール時はタイトル・補足とも `chatToolCallText`。通常はprimary／secondary | タイトルと補足2。外側の垂直padding4 |
| 処理グループ：`SF/ChatMessageCells+CommandGroup.swift:186`、`:239` | 外側は `DisclosureCard`。内側ラベル10／medium、コマンド13／monospaced、出力10／monospaced | ラベル・出力secondary、コマンドprimary＋構文色 | グループ内8、展開内容の上8、出力の上8。カード内水平12／下12 |
| Reasoning：`SF/ChatMessageCells+Structured.swift:192` | 展開内容13／regular。短文も13／regular。長文の見出しは共通カードの10／medium | 展開内容secondary、短文 `chatToolCallText` | 展開内容は行間3／上8 |
| サブエージェント行：同ファイル`:7` | 名前13、説明10 | primary／secondary。状態アイコンは意味色 | 名前と説明2、水平12／垂直8 |
| 処理中・経過情報：同ファイル`:67`、`:145` | 状態語13。`ShimmerTextView` にFontとpointSizeを渡す。経過10、警告10／medium | 状態語primary、経過secondary、警告文字primary＋警告アイコン色 | 状態行・補助行のStackは4、外側垂直4 |
| タスク：`SF/ChatMessageCells+TaskList.swift:16` | 見出しは共通カード。項目13、実行中はsemibold | 未完了primary、完了secondary＋取り消し線 | 項目間8、見出し後8 |
| 質問：`SF/UserQuestionCell.swift` | 質問13／semibold、回答13、補助10／regularまたはmedium | primary／secondary、状態色 | 外側12、内部4／8、一部の名前・説明間2 |
| 圧縮中表示：`SF/CompactingIndicatorCell.swift` | 13×倍率／italic | secondary等の既存状態表現 | 内容Stackは4 |
| 時刻：`SF/ChatMessageCellsCommon.swift:22` | 10×倍率／regular、数字は等幅 | `chatTextSecondary` | 本文との間隔は呼び出し側で主に4。`.distantPast` は非表示 |
| 料金：`SF/ChatMessageCells+Basic.swift:148` | **9**×倍率／monospaced | secondaryのopacity 0.7 | 右寄せ。時刻の10ptとは別指定 |
| コード：`SF/ChatCodeBlock.swift:12`、`SF/RichMarkdownView.swift:137` | コード本文13／monospaced、言語・コピー10。インラインコードは13.5／monospaced | 本文は構文色、補助secondary、インラインコードaccent | 主に水平12、垂直8／12。独立コードViewは水平スクロールあり |
| 差分：`SF/ChatMessageCells+Structured.swift:350` | ファイル補足10、行番号・差分本文10／monospaced | primary／secondary、追加・削除・構文の意味色 | セクション間12、コード行Stackは0 |
| トランスクリプト全体：`SF/ChatTranscriptView.swift:169` | 各セルへ委譲 | 背景は `chatBackground` | 種別にかかわらずブロック間12、外側水平16／垂直12 |
| 上部の補助ストリップ：`SF/ChatSessionAccessories.swift` | 主に `DSFont.caption`／`captionStrong`／`monoCaption`。独自の文字倍率参照なし | primary／secondary、選択・状態色 | 主に4／8、外側水平16 |
| チャットと入力欄：`SF/ChatSessionView.swift:117` | 本文フォントを直接指定しない | `chatBackground` | 外側Stackは0。本文幅・入力欄幅・末尾の逃し余白は既存レイアウトへ委譲 |

上部ストリップ、入力欄、承認操作、履歴ピッカーは調査対象だが、今回の文字体系変更の対象はトランスクリプト本文とそのカード・補助表示に限定する。

### 文字の正本

`DS/TranscriptTypography.swift` に、役割から文字指定と間隔を返す小さな正本を置く。既存の `Tokens.swift`、`ChatFontSettings.swift` の定義自体は変更しない。

新規公開面は次に固定する。

- `TranscriptTypography.Role`：下表の役割。`CaseIterable`、`Equatable`、`Sendable`。
- `TranscriptTypography.Style`：`baseSize: CGFloat`、`weight`、`design`、`ink` を持つ比較可能な値。
- `weight` はregular／medium／semibold／bold、`design` はsystem／monospaced、`ink` はprimary／secondary／tool／accentを表す値。
- `style(for:) -> Style`
- `pointSize(for:scale:) -> CGFloat`
- `font(for:scale:) -> Font`
- `color(for:) -> Color`
- 後述する間隔定数、`BlockRole`、`gap(after:before:)`。

数値・役割の導出は設定保存、I/O、時計、ViewModelに依存しない。`font` はシステムフォントを構築し、`color` は描画時に既存の `DSColor` を解決する。テーマ色を起動時の `static let Color` に固定しない。

| Role | 基準pt | weight | design | ink |
|---|---:|---|---|---|
| `body` | 15 | regular | system | primary |
| `bodyStrong` | 15 | semibold | system | primary |
| `heading1` | 26 | bold | system | primary |
| `heading2` | 19 | bold | system | primary |
| `heading3` | 16 | semibold | system | primary |
| `heading4` | 15 | semibold | system | primary |
| `heading5` | 15 | semibold | system | primary |
| `heading6` | 15 | semibold | system | primary |
| `processSummary` | 15 | semibold | system | tool |
| `metadata` | 10 | regular | system | secondary |
| `metadataStrong` | 10 | medium | system | secondary |
| `code` | 13 | regular | monospaced | primary |
| `codeMetadata` | 10 | regular | monospaced | secondary |
| `inlineCode` | 13.5 | regular | monospaced | accent |

`ink` の対応はprimary→`DSColor.chatTextPrimary`、secondary→`chatTextSecondary`、tool→`chatToolCallText`、accent→`chatAccent`。

- 通常本文を15ptへ統一する。既存H1〜3、インラインコード、コード本文の基準サイズは維持する。
- 処理の要約は15pt／semiboldへ統一する。カードの寸法・装飾を拡大して強調しない。
- 時刻と料金は10ptへ統一する。料金の追加opacity 0.7を除き、補助色の正本を使う。表示文字列・桁・通貨書式は変えない。
- エラー、警告、差分、完了状態、リンク、構文ハイライトの意味色は維持する。通常文字の階層化のために意味色を消さない。
- `DisclosureCard` の通常タイトルは `processSummary` の字体とprimary、ツールタイトルは同字体とtoolを使う。subtitleの既存 `isToolCall` による色分岐は維持する。
- 太字・斜体・取り消し線など本文内容や状態が持つ意味は維持する。状態によるsemiboldは `bodyStrong` へ接続する。

既存窓口は次のように委譲する。

| 既存窓口 | 正本への委譲 |
|---|---|
| `ChatTypography.bodyFontSize` | `body` のpointSize |
| `ChatTypography.codeFontSize` | `inlineCode` のpointSize |
| `ChatTypography.heading1FontSize`〜`heading3FontSize` | 対応する見出しのpointSize |
| `ChatScaledFont.body`／`bodyPointSize` | `body` のFont／pointSize。基準13→15は今回の意図した変更 |
| `ChatScaledFont.caption`／`captionStrong` | `metadata`／`metadataStrong` |
| `ChatScaledFont.mono`／`monoCaption` | `code`／`codeMetadata` |

既存API名は削除しない。これらのファイルにサイズ・倍率計算の別正本を残さない。

### 間隔の正本と適用箇所

以下は `TranscriptTypography` の定数とし、右列の既存トークンを参照する。文字倍率では拡大しない。

| 新規定数 | 値 | 使用箇所／既存トークン |
|---|---:|---|
| `withinAnswer` | 8 | 同じ回答内、Markdownとコード間、展開した処理カード間。`DSSpacing.s` |
| `betweenAnswers` | 16 | 入力後の内容、処理・補助表示から回答本文への切替。`DSSpacing.l` |
| `majorSection` | 24 | 次のユーザー入力の前。`DSSpacing.xl` |
| `metadataGap` | 4 | 本文と時刻、タイトルと補足、補助行。`DSSpacing.xs` |
| `textLineSpacing` | 4 | 既存の行間3指定とMarkdown段落の追加行間。`DSSpacing.xs` |
| `cardHorizontalInset` | 12 | 既存カードの水平内側余白。`DSSpacing.m` |
| `cardVerticalInset` | 8 | 既存カードの垂直内側余白。`DSSpacing.s` |
| `codeContentInset` | 12 | コード本文の既存内側余白。`DSSpacing.m` |
| `transcriptHorizontalInset` | 16 | トランスクリプトの既存水平余白。`DSSpacing.l` |
| `transcriptVerticalInset` | 12 | トランスクリプトの既存上下余白。`DSSpacing.m` |

適用上の規則：

- `AgentMessageBody` のMarkdown／コード間は12→8。
- 段落は下8、箇条書き項目は下4。リストの字下げ・番号・マーカーは既存描画を維持する。
- 見出しの上／下余白はH1＝0／8、H2＝16／8、H3〜6＝8／8。数値は正本から取得する。
- Markdownのmarginは隣接ブロック間で合成され得る。二つの指定値を単純加算した値を実測間隔と報告しない。
- 表のセル余白は既存の垂直4×倍率／水平8×倍率を維持する。表への新しい行高固定は行わない。
- 差分・コマンドの連続コード行にあるStack間隔0を8へ置き換えない。
- `DisclosureCard` 外側の垂直padding4は除き、隣接ブロック間隔を親側で一度だけ与える。展開内容の上余白8は維持する。
- 枠線幅、アイコン寸法、吹き出しの最大幅、角丸、コピー操作の押せる領域、ゼロ間隔によるコードの連結は文字階層の間隔とは別であり、変更しない。

### 回答内・回答切替・大区切りの判定

時刻や文字列内容から「同じ回答」を推測しない。既存のトランスクリプトブロック順序を使う。

新規 `TranscriptTypography.BlockRole` は `user`、`answer`、`process`、`auxiliary` の4種類とする。`gap(after:before:)` の期待値は次に固定する。

| 直前＼現在 | user | answer | process | auxiliary |
|---|---:|---:|---:|---:|
| 直前なし | 0 | 0 | 0 | 0 |
| user | 24 | 16 | 16 | 16 |
| answer | 24 | 8 | 8 | 8 |
| process | 24 | 16 | 8 | 8 |
| auxiliary | 24 | 16 | 8 | 8 |

連続する回答メッセージは分割出力として8ptを維持する。「回答切替16pt」は上表の表示上の境界を指し、バックエンドのturn IDを新たに推定する仕様ではない。

`SF/ChatTranscriptGrouping.swift` の既存 `ChatTranscriptBlock` に、新規の読み取り専用 `typographyRole` を追加する。

| 既存ブロック／ChatItem | typographyRole |
|---|---|
| `.single(.userMessage)` | user |
| `.single(.agentMessage)` | answer |
| `.commandGroup` | process |
| `.single` のreasoning／commandExecution／fileChange／subAgentMarker／taskList／userQuestion | process |
| `.single` のerror／turnCost | auxiliary |

- 既存のグループ化、順序、ID、表示件数制限、空出力の扱いは変更しない。
- `ChatTranscriptView` は表示対象ブロックの直前・現在の役割を正本へ渡す。最初の表示ブロックは直前なしとする。
- 親Stackの一律12ptと可変paddingを重ねない。親Stackは0とし、各ブロックの上側へ正本のgapを一度だけ適用する。
- 「以前のメッセージを表示」ボタンと先頭ブロックの間は16pt。処理中表示・圧縮中表示の前は8pt。
- 末尾のcomposer回避用スペーサー、そのID、高さ計算を維持する。
- 全履歴の再走査、スクロール位置からの間隔変更、描画中の状態更新は追加しない。

### Viewごとの接続義務

正本を定義しただけでは合格しない。以下の実際の描画経路へ適用する。

| View／描画箇所 | 必須接続 |
|---|---|
| `UserMessageCell`、`ErrorMessageCell`、`AgentMessageBody` | body、本文・補助間隔、回答内間隔。エラーの意味色は維持 |
| `ChatTimestampText`、`TurnCostCell` | metadata／codeMetadata。書式・表示条件は維持 |
| `DisclosureCard` | processSummary、metadata、metadataGap。通常／ツールの色分岐を維持 |
| `ReasoningSummaryView` | 短文・折りたたみ見出しの字体をprocessSummaryへ統一。展開本文はbody＋secondary |
| `CommandGroupCell`、`CommandGroupExecutionRow` | 親子双方の処理見出し、展開内容間8、コード・出力・補助字体 |
| `CommandExecutionCell`、`FileChangeCell` | 共通見出し、コード・補助字体、セクション間8。差分の意味色と行の間隔0を維持 |
| `TaskListCell`、`UserQuestionCell` | 本文15、強調本文15／semibold、補助10。内容間8・補助間4 |
| `SubAgentMarkerCell` | 名前はprocessSummaryの字体＋primary、説明はmetadata、名前と説明間4 |
| `ThinkingIndicatorCell`、`RunningTurnStatusView`、`CompactingIndicatorCell` | body／metadata。状態表現・斜体・アニメーションの挙動を維持 |
| `RichMarkdownView` | 本文・H1〜6・インラインコード・コードブロック・表本文と間隔 |
| `CodeBlockView`、`ChatCodeCard` | 言語等の補助字体、コード字体、既存カード内余白 |
| `ChatTranscriptView` | ブロック境界のgap、履歴ボタンの補助字体、外側余白 |

`ChatMessageCopyButton` は既存の `ChatScaledFont.captionStrong` を通じて正本へ接続されるため、製品ファイルの変更を要求しない。

### 既存設定・動作の不変条件

- `DS/ChatFontSettings.swift:7` の保存キー `phlox.chat.fontScale`、既定1.0、最小0.8、最大2.0、刻み0.1を維持する。
- View側の `ChatFontSettings.adjusted(from: chatScale, by: 0)` による補正を維持し、正本では受け取った有効倍率を一度だけ掛ける。
- `macos/App/PhloxApp.swift` の `FontSizeCommands` と、`DashboardViewModel.adjustTerminalFontSize(by:)` の既存経路を維持する。文字サイズ操作がターミナル設定にも作用する現行仕様を変更しない。
- `RichMarkdownView.themeCacheKey(themeID:scale:)` のテーマIDと倍率による分離を維持する。
- `ThinkingIndicatorCell` が `ShimmerTextView` へ渡すFontとpointSizeは同じbodyサイズとする。片方だけ更新しない。Reduce Motion時の静止表示も確認対象とする。
- 本文・見出し・箇条書きの `.fixedSize(horizontal: false, vertical: true)` を維持する。表・表セルには追加しない。
- `ChatTranscriptView` を `LazyVStack` へ変更しない。既存の予算、表示範囲、`.equatable()`、スクロール追従、ジャンプ、入力位置検出を維持する。
- コピー内容、展開条件、出力省略・全文展開、質問の回答操作、AX identifier、hoverでの時刻・コピー表示条件を維持する。
- `ChatSessionView`、`ChatComposer`、`ComposerLayout`、`GridChatColumn`、`ChatSessionAccessories`、ViewModel、クライアント、保存形式、パッケージ依存、App設定は変更しない。
- 文字サイズや間隔を新しいユーザー設定へ増やさない。正本に汎用テーマエンジンや登録機構を追加しない。

## 成功基準

### 1. Swift Testingで役割と値を凍結する

PMが `AcceptanceTranscriptTypographyTests.swift` を作成する。

- Roleの集合と各Styleのサイズ・太さ・design・inkを、上表の独立したリテラルで検証する。実装の `allCases` やStyle一覧から期待値を生成しない。
- 倍率0.8／1.0／1.5／2.0で、役割ごとのpointSizeが基準値×倍率になることを検証する。
- 同一倍率でH1 ≥ H2 ≥ H3 ≥ H4＝H5＝H6＝body＝processSummary > metadata。
- bodyStrongとbodyのサイズは同じで、太さが区別される。
- code＝13、inlineCode＝13.5、codeMetadata＝10の基準値と等幅指定を検証する。
- 間隔の値と `majorSection > betweenAnswers > withinAnswer > metadataGap` を検証する。
- `gap` の上表20条件を固定する。文字倍率を変えても間隔値は変わらない。
- 正本の取得によってUserDefaultsへの書き込み、プロセス、通信を発生させない構造をレビューする。

PMが `AcceptanceTranscriptTypographyIntegrationTests.swift` を作成する。

- `ChatTranscriptBlock.typographyRole` の各既存ケースとcommandGroupの対応を独立した期待値で検証する。
- 2件の連続コマンドが既存どおり1グループになり、ID・順序・件数が変わらないことを検証する。
- 「ユーザー→回答→回答→処理グループ→回答→料金→ユーザー」のgapが `[0, 16, 8, 8, 16, 8, 24]` になることを検証する。
- 表示範囲を途中から開始したとき、先頭ブロックへ24pt等の余白を持ち越さない。
- `ChatTypography` の既存APIが従来のMarkdown基準値を返すこと、`ChatScaledFont.bodyPointSize` が正本のbodyへ一致することを検証する。
- 非空の日本語本文、長い見出し、コード、処理カードを、実セルの `NSHostingView`／`ImageRenderer` で描画する。画像生成の成功は可読性の合格と区別する。

既存の `ChatFontScaleAcceptanceTests`、`ChatFontScaleWhiteBoxTests`、Markdownの切り詰め防止、表レイアウト、コードカード、処理グループ、質問・タスク、スクロール関連テストを維持する。既存期待値を変更して新仕様へ合わせる必要が生じた場合、Cursorは編集せず、凍結前ならPMが契約上の衝突を解消し、凍結後なら再契約する。

### 2. Rubyで実Viewへの配線と不変条件を検査する

PMが `.claude/scripts/task40-wiring.rb` を作成する。task38／task39の固定SHA比較、構造抽出、自己検査を見本とし、巨大な既存検査を丸ごと複製しない。

必須検査：

1. `TASK40_BASELINE` は必須。`tasks/task-40.md` の `baseline_commit` と、コミットへ解決したSHAが一致すること。
2. 未設定、プレースホルダ、ブランチ名、`HEAD`、`HEAD~1`、`HEAD^`、`@`、不正・曖昧・取得不能なSHAを拒否する。
3. 基準は実装前に凍結したコミットで、現在のHEADの祖先であること。基準時点には新しい `TranscriptTypography.swift` が存在しないことを確認する。
4. 基準SHAのblobにある受け入れテスト2ファイルとRuby検査自身が、作業ツリーとバイト単位で一致すること。
5. 既存製品の保護対象は `git show <固定SHA>:<path>` と作業ツリーを比較する。`git show HEAD:<path>` へのフォールバックや現在同士の比較は禁止。
6. **固定SHAが現在のHEADと等しいことだけでは拒否しない。** 凍結コミット上の未コミット実装は許容し、実装前の内容・凍結テストの同一性で正しい基準を判定する。
7. Viewごとの接続表を固定し、実際の `body`、描画ヘルパー、Markdownテーマクロージャから正本または委譲窓口へ到達することを確認する。
8. 対象文字のサイズ・太さ・役割色・間隔に旧指定が残っていないことを確認する。特に料金の `9 * scale`、行間3、説明間2、共通見出しのcaptionStrong、回答内12、一律ブロック間12を検出する。
9. 新たな `.system(size: 数値)`、`FontSize(数値)`、数値×倍率、対象箇所への直値padding／spacingを拒否する。既存の枠線・アイコン・幅・コード連結0は、固定した対象箇所単位で例外化し、ファイル丸ごとの除外にしない。
10. コメント、文字列、未使用宣言、`if false` 内に正本名を書いただけでは合格させない。親へ正本を指定した後、子で旧字体へ上書きした場合も拒否する。
11. `ChatTypography`／`ChatScaledFont` の委譲、ShimmerのFontとpointSize、Markdownのテーマキャッシュ、ブロック分類からgap適用までを確認する。
12. 変更許可箇所は描画属性と本契約の分類接続に限定する。操作クロージャ、ID、コピー内容、条件分岐、スクロール処理、コード・差分処理の残余を凍結blobと比較する。ファイル全体からfont／padding行を無条件削除して比較する方式は使わない。
13. `ChatSessionView`、設定・幅計算・ViewModel等の変更禁止対象を固定SHAと比較する。
14. ファイルや必須シンボルを抽出できない場合は非ゼロ終了する。見つからなかった検査を成功扱いにしない。

`--selftest` は本番と同じ検査関数を使い、実ファイルを変更せずメモリ上のfixtureで実行する。

- 正例：契約どおりの直接参照、許可した委譲、意味を変えない空白・コメント変更。
- 負例：接続削除、誤った役割、子Viewの上書き、旧直値の復活、倍率の二重適用、gapの二重加算、同一回答への24pt、コメントだけの参照、未使用ヘルパー、`if false`、必須ケース欠落。
- 基準検査の負例：SHA欠落・HEAD指定・無効SHA・非祖先・実装済み基準・blob取得失敗・凍結テスト改変・検査自身の改変・契約SHAとの不一致。
- 各負例は正例へ違反を1件だけ加え、その違反を理由としてNGになることを確認する。
- Rubyによる構造検査をSwiftの完全な意味解析や実描画検証とは扱わない。

### 3. 品質ゲートを実行する

調査で確認した正本は `.claude/verify.sh` と `macos/scripts/run-swift-tests.sh`。既存verifyは8パッケージ、更新隔離検査、`git diff --check` を実行する。新規task-40のRuby検査は現時点では未接続であり、PMが凍結時に接続する。

パッケージ確認：

```sh
~/.agents/scripts/compact-test task40-packages bash macos/scripts/run-swift-tests.sh DesignSystem SessionFeature DashboardFeature
```

Ruby検査。`<固定SHA>` はPMが凍結した実値へ置換する。

```sh
~/.agents/scripts/compact-test task40-wiring-selftest ruby .claude/scripts/task40-wiring.rb --selftest
~/.agents/scripts/compact-test task40-wiring env TASK40_BASELINE=<固定SHA> ruby .claude/scripts/task40-wiring.rb
```

統合確認：

```sh
~/.agents/scripts/compact-test task40-integration bash .claude/verify.sh
```

Appビルドは `macos` ディレクトリで実行する。DerivedDataはPM所有の今回専用絶対パスへ置換する。

```sh
~/.agents/scripts/compact-test task40-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <今回専用DerivedData絶対パス> -destination platform=macOS build
```

- `Package.swift`、`macos/project.yml`、既存検証スクリプトを凍結前に再確認する。
- 今回の検索では専用SwiftLint／SwiftFormat設定は見つからなかった。未設定の検査を実行済みと扱わず、新規ツールを導入しない。
- パッケージテスト、Appビルド、Ruby検査、GUI確認は別々に結果を記録する。警告・実行不能・失敗を省略しない。
- テストコマンドは必ず `compact-test` またはそれを内部で使う正本経由とし、スキップ指定を追加しない。

### 4. PM目視ゲートを課金なしで実施する

#### 調査で確認した到達手段

復元失敗プレースホルダは、`SessionSpawnService.makeRestoreErrorChatSession` が `DisconnectedStructuredAgentClient` を渡し、実クライアントの `startNew`／`restore` を呼ばずに構築する。

**「transcriptが空」は現コードでは厳密には異なる。** `SF/ChatSessionViewModel.swift:906` の `markRestoreFailed` はエラーChatItemを1件追加する。通常の回答・処理カードはないが、エラー行と入力欄を確認する経路として使える。sessions.jsonからの到達はPM確認済みという依頼時の情報を前提とし、今回GUIで再確認したとは扱わない。

SessionFeature全体を検索した範囲では、混在する会話全体を描く既存 `#Preview` は見つからなかった。確認できたPreviewは `ChatInputHistoryScrubber.swift` のスクラバー用である。一方、課金なしの描画手段は存在する。

| 既存テスト | 利用できる手段 |
|---|---|
| `SessionFeatureTests/AcceptanceMarkdownNoTruncationTests.swift` | `NSHostingView` で日本語長文・見出し・共通カードの折り返し高さを取得 |
| `SessionFeatureTests/AcceptanceCommandGroupRecapHeaderTests.swift` | 固定ChatItemから実行中／完了後の `CommandGroupCell` を `ImageRenderer` で描画 |
| `SessionFeatureTests/AcceptanceChatCodeCardTests.swift` | コードカードと複数行コマンドを描画 |
| `SessionFeatureTests/AcceptanceFileChangeCodeViewTests.swift` | 差分セルを描画 |
| `DashboardFeatureTests/ChatMessageCellsRenderTests.swift` | 本文・Reasoning・コマンド・差分等の実セルを直接描画 |

これらは完成済みの日本語混在会話用目視ハーネスではない。PMが凍結前に、既存方式を使って新規のSessionFeature受け入れテスト内へ目視用fixtureを準備する。**実claude／codex／cursorの起動やメッセージ送信を、準備・テスト・PM目視の条件にしない。**

#### A. 隔離Debug：エラー行と入力欄

1. 今回の変更を含む専用Debugを、PMが確認済みの隔離データ・設定経路で起動する。通常のsessions.jsonを加工せず、通常版や別セッションを停止しない。
2. sessions.jsonの復元失敗プレースホルダを表示し、エラー見出し、エラー本文、時刻、入力欄を撮影する。送信・再試行・セッション作成を行わない。
3. 既存の「文字を大きく」「文字を小さく」で倍率1.0→2.0→0.8→1.0を確認する。通常設定への混入を防ぎ、ターミナル文字設定も変わる現行経路を踏まえて前後の値を記録する。
4. エラー全文の折り返し、時刻との区別、入力欄への重なり、末尾へのスクロール到達を確認する。
5. この画像を、日本語回答・箇条書き・処理カードの目視成功には数えない。

#### B. SessionFeature fixture：混在する会話

PM所有のテストfixtureは次を含める。

- 日本語の長文段落を複数、H1〜H6、長く折り返す節見出し。
- 長い箇条書き、番号付き箇条書き、入れ子。
- インラインコード、Swiftコードフェンス、長いコード行。
- 連続コマンド2件のグループと、Reasoning等で区切った別グループ。折りたたみ・展開の両状態。
- 複数行コマンド、20行を超える出力、差分、タスク、質問、時刻、料金。
- ユーザー入力を2回以上置き、8／16／24ptの境界を同時に比較できる並び。

手順：

1. 実際の `ChatTranscriptView` を、既存の `transcript:` 引数へ固定ChatItemを渡してホストする。ViewModelにはテスト内の通信しないクライアントを渡し、実バックエンドを起動しない。個別セル画像も補助として取得する。
2. `NSHostingView` を用いた描画と画像取得をPMが凍結前に実走する。展開操作が必要な箇所はホストした実Viewを操作し、別途作った見本カードで代用しない。
3. 幅360pt／720pt、倍率0.8／1.0／2.0を確認する。長い会話は全高画像または連続画像で末尾まで記録し、既存テストの固定420pt高をそのまま使って下部を切り落とさない。
4. 設定用UserDefaultsはテスト専用とし、Viewが実際に参照する保存先を確認する。suiteを作っただけで隔離できたと仮定しない。
5. 本文・見出し・補助情報の読順、箇条書きの重なり、コードの水平到達、処理見出しの折り返し、カード間隔、展開時の欠けを確認する。
6. 明るいテーマと暗いテーマで確認し、使用テーマ名を記録する。テーマ変更と倍率変更を連続して行い、キャッシュが古い字体・色を返さないことを確認する。
7. 処理中表示は通常動作とReduce Motionの両方で確認する。文字サイズ変更による切れと、Font／pointSizeの不一致がないことを確認する。

画像生成だけ成功して目視していない場合、読順・欠け・重なりは未検証とする。fixtureのホストや画像取得が成立しなければ当該ゲートは未達であり、課金セッションで代替しない。

PMは `docs/agent-output/visual-task-40.md` に、コミット、App／fixtureの別、幅、倍率、テーマ、展開状態、画像、合否、未検証項目を記録する。UI-03の完了にはAとBの両方を必要とする。

## レビュー観点（Rubric）

- 本文15、処理要約15／semibold、補助10の差が実Viewへ適用され、正本だけ正しくて描画が旧指定のままになっていない。
- システムフォント、既存H1〜3・コードサイズ、文字倍率の保存・操作経路を維持している。
- 8／16／24ptの境界が上表に一致し、親Stack・カード外側paddingとの二重加算がない。
- 連続する回答やコマンドのグループ化、ID、表示範囲、スクロール、入力位置検出を変えていない。
- コード、差分、表、意味のある太字・斜体・状態色を通常本文と機械的に同一化していない。
- ShimmerのFontとpointSize、Markdownのテーマ・倍率キャッシュ、文字拡大後の高さが整合する。
- 折り返し高さの保護を維持し、表へのfixedSize、LazyVStack再導入、描画中の状態更新がない。
- Ruby検査が固定SHAのblobと比較し、自己比較・未使用コード・子Viewの上書きを検出する。selftestは本番関数へ単一違反を与えている。
- Cursorがテスト・検査・契約を変更せず、PMが作成した凍結条件を満たしている。
- Appの復元失敗経路と混在会話fixtureの証拠を分け、エラー行だけで会話全体を検証したと報告していない。
- 新規ライブラリ、巨大なカード、追加設定、汎用基盤を導入せず、文字と余白の整理に収まっている。
- 未実行・失敗・警告を明示し、課金セッションの起動を完了条件にしていない。
## PM 採択時の調整（2026-09-13）

- 受け入れテスト（Swift Testing 2 ファイル）・配線検査 `task40-wiring.rb` の作成は Cursor（テスト作成担当）に委譲し、PM が凍結前に RED と `--selftest` を確認する。
- 成功基準 1 の統合テストのうち「実セルの `NSHostingView`／`ImageRenderer` で描画する」項目は凍結テストから外し、PM 目視ゲート B のハーネス（`macos/Packages/SessionFeature/Tests/SessionFeatureTests/Harness/TranscriptTypographyRenderHarness.swift` 等、凍結対象外・PM 所有）として実装する。凍結テストは値・順序・`typographyRole`・`gap` 系列の決定的検査に限定する。
- 配線検査の項目 12（残余の凍結 blob 比較）は `allowed_paths` に列挙した製品ファイルに限定し、それ以外の変更禁止対象は「変更なし（blob 同一）」で検査する。
- ユーザー本文 13→15pt の統一は意図した変更として採択する（回答本文と同じ本文サイズにそろえる）。それ以外の既存サイズ（H1〜3・コード・インラインコード）は維持する。
