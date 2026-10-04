---
status: completed        # 実装済み。現行構成は architecture/ にある（本書は設計時点の記録）
last-verified: 2026-10-03
---

# ファイルツリー（右サイドバー）・マークダウンのブロック編集・HTML 表示 — 設計書

> **実装済み**: 現行構成は [architecture/file-explorer-and-markdown-editing.md](../architecture/file-explorer-and-markdown-editing.md)。

> **このドキュメントの役割**: 右サイドバー（インスペクタ）に VS Code 風のディレクトリツリーを足し、
> ファイルを開いて編集できるようにする機能と、マークダウンをレンダリングした状態のまま編集する機能・HTML の表示機能の
> 要件・設計・既存機能との互換性・テスト計画。
> **書かないもの**: 実装後の現行構成（→ 実装完了時に `architecture/` へ蒸留）、決定の経緯の不変記録
> （→ 実装着手時に ADR を起こす。本書 §8 が下書き）。
>
> **改訂履歴**: 2026-10-02 初版。同日、Codex（gpt-6.1-sol）との 5 ラウンドのレビュー議論を反映して改訂
> （ファイルアクセスの安全性・バイト単位の保存・編集状態の契約・描画方式・HTML の権限・終了時の未保存確認）。
> 同日、Claude Design の UI モック（`specs/ClaudeDesign/1〜6`）で確定した見せ方と操作の細部を反映（§3.8、§9）。
> 同日、Codex（gpt-6.1-sol）の最終レビュー（判定: 条件付きで実装に入ってよい）の条件を反映（複数ウィンドウの下書き・開く要求のルート固定・分割幅の事実訂正・テスト計画の補完）。

## 0. 要点（平易な言葉で）

- **ツリーは右サイドバーの新しいタブ「ファイル」に置く。** 今ある「セッション / 使用量」の切り替えに 3 つ目を足すだけなので、
  幅の調整・狭いときの重ね表示・⌃⌘I での開閉はすべて既存の仕組みがそのまま効く。
- **ファイルを開く先は、今もある中央の「ファイルタブ」。** ⌘P で開くのと同じタブ・保存処理・競合ダイアログを使う。
- **マークダウンはブロック単位で編集する**（ユーザー決定 2026-10-02）。見出し・段落・表などはレンダリング表示し、
  クリックしたブロックだけがその場で原文の入力欄に変わる。保存される Markdown は、触ったブロック以外 1 バイトも変わらない。
- **HTML は閲覧専用のレンダリング表示＋ソース編集**（2026-10-02 追加要望）。WKWebView で表示し、スクリプトは常に止め、
  ページからの外部通信は常に遮断する。HTML をレンダリング状態のまま編集する機能は作らない。
- **既存のファイル読み書きの穴を先に塞ぐ**（レビューで判明）。worktree 外を指す symlink 経由で外のファイルを読み書きできる・
  Unicode の表記ゆれで未保存や競合を見逃す・BOM が保存で消える・アプリ終了やウィンドウを閉じるときに未保存の確認が無い。
  ツリーで開けるファイルが増えるとこれらが表面化するため、最初の出荷単位としてここを直す。

## 1. 現状（2026-10-02 時点のコードで確認）

> 注意: `architecture/terminal-editor-panels.md`・`specs/terminal-editor-panels.md`・ADR 0148 が述べる
> 「trailing ドロワー」「⌘⌥T/⌘⌥E」は現行コードに存在しない（子タブ方式へ移行済み）。本書はそれらでなく下記のコードを根拠にしている。

| 要素 | 現行実装 | 本機能との関係 |
|---|---|---|
| 右サイドバー | `InspectorView`（`DashboardFeature/Dashboard/UsageSidebarView.swift`）。`AppRouter.inspectorTab: InspectorTab`（`.session` / `.usage`） | `.files` を足す |
| 右サイドバーの幅 | `PaneWidthPolicy`（中央 480pt 下限）。`DSLayout.inspectorWidth` 260〜340pt、`@SceneStorage("pane.inspectorWidth")`。足りなければ重ね表示 | 変更なし |
| ファイル編集 | 子タブ `ChildTab.file(String)`（Git ルート相対パス）。`FileTabView`（`Tabs/SessionTabsContainer.swift`）＋ `FileTabDocument`（`Tabs/FileTabDocument.swift`）＋ `CodeTextEditor`（NSTextView・TextKit 1） | 開く先として再利用し、表示モードを追加 |
| 下書きの所有 | `FileTabDocuments` を `DashboardView` の `@State` で保持（ウィンドウごと。`WindowGroup` なので複数ウィンドウあり得る） | ウィンドウごとのまま、App レベルの登録簿を足す（§3.6） |
| ファイルを開く入口 | ⌘P の `NSOpenPanel`（`DashboardView.chooseFileToOpen`）、変更タブの「ファイルタブで編集」 | ツリーを 3 つ目の入口に |
| パスの検査 | `WorkingTreeService.fileURL(for:)` は絶対パス・空要素・`.`・`..` を拒否するだけで、**symlink 解決後の包含確認は無い**。`save` は `resolvingSymlinksInPath()` の先へ書く。読み書きのたびに `git rev-parse --show-toplevel` でルートを再解決する | §3.2 で修正 |
| 未保存・競合判定 | `FileTabDocument.isDirty` と `save` の競合判定は `String ==`（**Unicode 正規等価で比較**するため、バイトが違っても等しいと判定され得る） | §3.3 で修正 |
| 終了処理 | `AppDelegate.applicationShouldTerminate` は冒頭で `cleanupGuard.beginCleanup()` を呼び、ファイル下書きの確認は無い | §3.6 で追加 |
| マークダウン描画 | `RichMarkdownView`（SessionFeature）。init で `TranscriptMarkdownPresentation.prepare`（改行正規化・閉じていない強調の補完）を通し、body で `.environment(\.openURL)` を固定で上書きする | チャット用の前処理なし・リンク処理注入可の init を足す（§3.4） |
| HTML 描画 | 無し（アプリ全体で WebKit 未使用）。App Sandbox は無効 | WKWebView を初導入（§3.5） |
| ファイル監視 | 無し | 本書でも入れない（§7） |

## 2. 要件

### 機能要件（FR）

| ID | 要件 |
|---|---|
| FR-1 | 右サイドバーに「ファイル」タブがあり、選択中セッションの Git ルート（Git でなければ作業ディレクトリ）をルートとするツリーを表示する。上部にルートのパスとブランチ名（detached HEAD はコミット短縮名、Git でなければ「Git 管理外」、取得失敗は空欄）を出す |
| FR-2 | フォルダは展開・折りたたみできる。並びはフォルダ先・名前の自然順 |
| FR-3 | ファイルをクリックすると中央の操作中の区画にファイルタブとして開く（既存なら前に出す）。単体表示へ切り替え、共通ターミナルの選択を解除する |
| FR-4 | 右クリックメニュー: 「右に分割して開く」「Finder で表示」「パスをコピー」。フォルダ行と、開けない行（ルート外を指す symlink 等）には「右に分割して開く」を出さない |
| FR-5 | 操作中のファイルタブに対応する行を「開いている行」として示す（薄い塗り＋太字）。キーボードで移動中の行（フォーカス）とは別の印にする |
| FR-6 | セッションの選択に追従する。同じルートなら展開状態を保つ。未選択時は空状態 |
| FR-7 | 更新ボタンで再読込できる。フォルダ展開時・保存時に該当フォルダを読み直す |
| FR-8 | `.md` / `.markdown` は既定でレンダリング表示。帯で「レンダリング / ソース」を切り替えられる |
| FR-9 | レンダリング表示でブロックをクリック（または選択して Return・アクセシビリティの「編集」操作）すると、そのブロックだけが原文の入力欄になる。Esc・ブロック外クリック・⌘Return で確定する |
| FR-10 | どちらの表示でも、未保存表示・⌘S 保存・外部変更の競合ダイアログは働く。編集中（未確定）のブロックも未保存として扱う |
| FR-11 | マークダウンのリンク: 文書の位置を基準に解決した worktree 内の `.md`/`.markdown`/`.html`/`.htm` はファイルタブで開く（ルート外は開かない）、`http(s)` はブラウザで開く、それ以外は無視 |
| FR-12 | 先頭の YAML front matter は 1 ブロックとして等幅表示し、原文編集のみ可能 |
| FR-13 | `.html` / `.htm` は既定でレンダリング表示（閲覧専用）。編集はソース表示で行う |
| FR-14 | HTML のレンダリング表示は未保存の draft を表示する。ソース表示から戻ったとき・再読込ボタン・保存時に再描画する |
| FR-15 | HTML から参照される worktree 内の CSS・画像・フォント・iframe を表示する。リンクのクリックは worktree 内の `.html`/`.md` ならファイルタブ、`http(s)` なら既定ブラウザ |
| FR-16 | アプリ終了時・ウィンドウを閉じるときに、未保存（未確定の編集を含む）のファイルがあれば「保存せず閉じる（終了）／キャンセル」を確認する |

### 非機能要件（NFR）

| ID | 要件 |
|---|---|
| NFR-1 | **バイト単位で保存を保証する**: 未保存判定・競合判定・往復テストは UTF-8 のバイト列（`Data`）で比較する。編集していないブロックのバイトは変えない。BOM・CRLF・混在改行・末尾改行の有無・Unicode の合成/分解表現を保つ |
| NFR-2 | ツリーは展開されたフォルダの直下だけを、メインスレッド外で読む。同じフォルダの読み込みは 1 本にまとめ、古い要求の結果は捨てる |
| NFR-3 | 通常の読み込み・保存・HTML 配信は、symlink 解決後の実パスがルート配下のものに限る（ルート外を指す symlink は読み書きとも拒否）。**検査と読み書きの間に symlink を差し替える悪意ある並行書き換えへの防御ではない**（保証外） |
| NFR-4 | ツリーはディスクを書き換えない。書き込みは `FileTabDocument` の保存経路だけ |
| NFR-5 | 1 MB 超・バイナリ（先頭 8 KB に NUL）は編集領域へ読み込まない。ブロック数 2,000 超または 500 KB 超のマークダウンはソース表示に固定する |
| NFR-6 | 既存の幅決定（`PaneWidthPolicy`）・タブ永続化（`phlox.sessionTabs.v1`）・凍結受け入れテストを変更しない |
| NFR-7 | HTML 表示: ページの JavaScript は常に無効（アプリが差し込むスクリプトは、専用の実行環境でリンクのホバーを拾う用途だけに使う。§3.5）。ページ由来の外部要求（画像・CSS・フォント・iframe・`@import` 等）は常に遮断。遮断ルールの準備が整う前・失敗時は読み込まない。**WebKit 自身の通信や sandbox 相当の隔離は保証しない** |
| NFR-8 | 文書は開いた時点のルートと相対パスに固定し、保存時にルートが消えていれば書かない（別のルートへ書かない） |

## 3. 設計

### 3.1 全体像

```
InspectorView ── [セッション | ファイル | 使用量]
                        │
                  FileTreeView ── FileTreeModel（ルートごと。ディレクトリ情報と展開状態だけ）
                        │ クリック            └─ FileTreeLoader（メインスレッド外。要求世代・同一フォルダ集約）
                        ▼
openFileTab(sessionID:, root:, relativePath:)   ← ⌘P・ツリー・リンクの共通関数（単体表示へ・共通ターミナル解除）
                        ▼
FileTabView ── FileTabDocument（draft が唯一の正本。ルート固定・Data 比較・編集状態を所有）
     ├─ ソース表示:              CodeTextEditor（現行）
     ├─ レンダリング表示（.md）:  MarkdownBlockEditor ── MarkdownBlocks（cmark-gfm で全体を 1 回パース）
     │                              └─ 各ブロック = RichMarkdownView(source:openURL:) / 編集中のみ CodeTextEditor
     └─ レンダリング表示（.html）: HTMLPreviewView（WKWebView・JS 無効・外部遮断）── WorktreeSchemeHandler
```

新規ファイルは `DashboardFeature/Sources/DashboardFeature/Files/`（ツリー）と `Tabs/`（マークダウン・HTML）に置く。
新しいパッケージは作らない。

### 3.2 ファイルアクセスの基盤修正（最初の出荷単位）

**(a) symlink の包含確認（NFR-3）**: `WorkingTreeService` の読み込み（`fileContents`）・保存（`save`）・絶対パス取得の
共通経路で、毎回「`resolvingSymlinksInPath()` 後の実パスがルート配下」かつ「通常ファイル」であることを確認する。
外なら `WorkingTreeServiceError.outsideRoot(resolvedPath)` を投げ、`FileTabView` は「このファイルは作業ツリーの外を指しています
（`<解決先>`）」と「Finder で表示」を出す。
これは**既存挙動の変更**: モノレポ等で worktree 外の共有ファイルへ symlink したファイルを、今はアプリ内で編集できるが、できなくなる。
変更タブの diff 表示（`git diff` の出力）は影響を受けない。

**(b) ルート固定（NFR-8）**: `FileTabDocument` は開いた時点で解決したルートを保持し、`WorkingTreeService` に
「ルート固定モード」（読み書きのたびに `rev-parse` しない）を足して使う。保存時にルートが存在しなければ書かずにエラー。
変更タブ側の既存の呼び方は変えない。

**(c) バイト単位の読み書き（NFR-1・NFR-5）**: 読み込みを `Data` で 1 回だけ行い、この経路に集約する:
サイズ上限（1,000,000 バイト。`EditorPanelViewModel.maximumEditableFileSize` は `private` なので共有定数へ移す）→
先頭 8 KB の NUL 検査 → 先頭 BOM の分離 → 厳密な UTF-8 復号。
`FileTabDocument` は `loadedDiskBytes: Data`・`bom: Data` を持ち、
保存候補 = `bom + Data(draft.utf8)`、`isDirty` = 保存候補 ≠ `loadedDiskBytes`、競合 = ディスクの現在の `Data` ≠ `loadedDiskBytes`。
`CodeTextEditor.updateNSView` の文字列比較も `utf8.elementsEqual` に変える（正規等価な変更で表示同期が省略されないように）。
`tooLarge` / `binary` / `outsideRoot` / `loadFailed`（非 UTF-8 等）は読み込み状態の enum にまとめ、
大きすぎる・バイナリには「既定のアプリで開く」（`NSWorkspace.shared.open`）を出す。

**(d) 開く共通関数**: `openFileTab(sessionID:root:relativePath:split:)` を作り、⌘P・ツリー・マークダウン/HTML のリンクがすべて通る。
`root` は要求した時点で固定したルートで、`FileTabDocuments.document(for:)` の文書生成まで渡す（表示時の作業ディレクトリで作り直さない）。
要求から完了までの間にセッションの作業場所が変わっていたら、要求を捨てる（別のルートの同名ファイルを開かない）。
中身は `router.viewMode = .single`・`router.commonTerminalSelected = false`・`router.tabs.updateLayout { $0.open(...) }`
（分割時は `splitRight`）。⌘P は現在 `commonTerminalSelected` を解除しておらず、共通ターミナル表示中に開くとファイルタブが見えない。
この既存の不足も同時に直す。ルート決定（`resolvedRepositoryRootPath() ?? rawWorkspacePath`）と `relativePath(of:under:)` も共有関数にする。

**(e) 終了・ウィンドウを閉じるときの確認**: §3.6。

### 3.3 ファイルツリー

**置き場所**: `InspectorTab` に `case files` を足し「セッション / ファイル / 使用量」にする。新しいペインは作らない
（`PaneWidthPolicy` は左サイドバー・中央・インスペクタの 3 領域を扱う純関数で、列を増やすと既存の幅テストと規則を作り直すことになる）。ADR 0090 の「インスペクタ＝補助情報」という位置づけが「補助情報とファイル操作」に広がる。

**型**

| 型 | 種別 | 役割 |
|---|---|---|
| `FileTreeEntry` | 値型 | `relativePath`・`name`・`kind`（`.directory` / `.file` / `.symlinkToDirectory` / `.symlinkOutsideRoot` / `.symlinkToFile`） |
| `FileTreeLoader` | `actor` | `children(of:)` を**メインスレッド外**で実行。`FileManager.contentsOfDirectory(at:includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])`。`.git` と `.DS_Store` を除く。同じフォルダの読み込み中は既存の Task を返す（集約）。結果には要求世代を付け、古い世代は捨てる |
| `FileTreeModel` | `@MainActor @Observable` | **ルート単位で共有するのはディレクトリ情報と展開状態だけ**: `root`・`childrenByDir`・`expanded`・フォルダごとの読込エラー |
| `FileTreeRows` | 純関数 | `visibleRows(childrenByDir:expanded:) -> [(entry, depth)]` |
| `FileTreeView` | View | 平坦化した行を `List(rows, selection:)` に深さぶん字下げで並べる。**選択（`selectedPath`）は View 側の状態**（同じルートを見る別ウィンドウ・別セッションと混ざらない） |

- **symlink**: ディレクトリへの symlink は**展開しない**（ルート内でも祖先へ戻るリンクによる無限展開を構造的に避ける）。
  ファイルへの symlink はルート内を指すときだけ開ける。ルート外を指すものは薄く表示し、開けない理由を出す。
- **クリック時の固定**: クリックの時点で sessionID・ルート・相対パスを固定して `openFileTab` に渡す
  （非同期読込の後でセッションが変わっていても、別のセッションに開かない）。
- **キーボード**: ↑↓ で移動（`List` 標準）、→ で展開（展開済みなら最初の子へ）、← で折りたたみ（折りたたみ済みなら親へ）、
  Return で開く。折りたたみで選択行が隠れたら親を選択する。
- **アクセシビリティ**: 行の value に階層レベルと展開状態、展開／折りたたみのアクセシビリティアクション。
- **更新**: ファイル監視は入れない。①更新ボタン ②フォルダ展開時 ③保存成功時に親フォルダ ④「ファイル」タブ表示時。
- **モデルの寿命**: `[ルートパス: FileTreeModel]` を `DashboardView` の `@State` で持つ。永続化しない。
- **空状態**: セッション未選択 →「セッションを選ぶと、その作業ディレクトリのファイルが表示されます」。ルートが読めない → 理由と更新ボタン。
- **巨大な直下一覧**: 1 フォルダ 5,000 件を超えたら先頭 5,000 件だけ表示し「ほか N 件（⌘P で開けます）」を出す。

### 3.4 マークダウンのブロック編集

**原則: `FileTabDocument.draft`（原文）が唯一の正本。** レンダリング表示は派生物で、編集は「draft の該当区間を置き換える」だけ。
リッチテキストから Markdown を組み立て直すことはしない。

**分割と描画 `MarkdownBlocks`（純関数）**

- 文書全体を 1 回、cmark-gfm でパースする。パーサーのオプションと拡張（table・strikethrough・tasklist・autolink・tagfilter 等）は
  MarkdownUI の `Parser/MarkdownParser.swift` の設定に合わせる。
- **編集用の区間**（原文）と**描画用の Markdown** を分ける:
  - ノードがある文書: 区間 *i* =「最上位ノード *i* の開始行 〜 次のノードの開始行の直前」（先頭の残余は最初の区間へ）。空行・
    ブロック内やブロック間の参照定義は区間に含まれ、**原文編集のときだけ見える**。
    描画用 Markdown = そのノードを `cmark_render_commonmark(node, options, 0)` で出力したもの。参照リンクは文書全体の規則
    （重複定義は最初が優先）で解決済みのインラインリンクになり、閉じていないコードフェンスもノード単位で閉じて出力される。
  - 空の文書（0 バイト）: 空のブロックを 1 つ出し「クリックして書き始める」を表示する。クリック（または Return）で原文編集。
  - ノードが無いが中身はある文書（空白のみ・参照定義のみ）: 全体を 1 つの「原文」区間として薄く表示し、クリックで原文編集。
  - front matter（1 行目が `---`、次の `---` 行まで）は cmark に渡す前に独立区間として切り出し、本文の行番号にはそのぶんのオフセットを加える。
- **不変条件**: 全区間の連結 = 原文（バイト一致）。区間は重複なく全行を覆う。
- 表の commonmark 出力は cmark の table 拡張（`extensions/table.c`）が持つ。**往復後の MarkdownUI での描画一致は未検証**で、テストで確かめる（§6）。
- 依存: `DashboardFeature/Package.swift` に `swift-cmark`（`from: "0.4.0"`、MarkdownUI と同じ指定）を明示する。解決済みの 0.8.0 を使い、新しいダウンロードは無い。

**描画部品**: SessionFeature の `RichMarkdownView` に public init `RichMarkdownView(source:openURL:)` を足す
（チャット用の前処理 `TranscriptMarkdownPresentation.prepare` を通さず、リンク処理を注入できる。ファイル用は別テーマ `fileMarkdownTheme` を使う）。
既存の init とチャットの挙動は変えない。

**編集状態の契約（`FileTabDocument` が所有）**

```swift
struct ActiveBlockEdit { let id: UUID; let baseVersion: Int; let range: Range<Int>; let original: String; var current: String }
var activeBlockEdit: ActiveBlockEdit?
var hasUnsavedChanges: Bool { isDirty || activeBlockEdit.map { $0.current != $0.original } ?? false }   // 比較は utf8
func commitActiveBlockEdit() -> Bool
```

- draft への反映は**確定時に 1 回だけ**（入力ごとには反映しない）。`version` は draft が変わるたびに増える。
- **確定点**: ブロック編集欄（`CodeTextEditor` の NSTextView）の `resignFirstResponder` で、
  「変換中（`hasMarkedText`）なら `unmarkText()` → `textView.string` を `activeBlockEdit.current` へ明示同期 → `commitActiveBlockEdit()`」。
  `textDidChange` の通知順には頼らない。⌘S・モード切替は同じ処理を明示的に呼んでから実行する。
- **確定できないとき**（`baseVersion` が現在の `version` と違う）: 置換せず、編集内容を保持し、保存・モード切替を拒否して帯に理由を出す。
  編集中は文書の undo を受け付けないので通常は起きないが、防御として置く。
- **ナビゲーションや View の撤去が先に起きた場合**: `dismantleNSView` では未確定の文字を `activeBlockEdit.current` へ同期するだけ。
  編集状態は文書に残り、タブに戻ると編集中のまま復元される。`id` で二重確定と、破棄後の古いコールバックによる復元を防ぐ。
- **閉じる確認・セッション削除確認・`dirtyFileNames`・終了確認**は `hasUnsavedChanges` を見る（未確定の編集も含む）。
- **undo**: ①編集中の ⌘Z はブロック内の入力を取り消す（NSTextView の履歴）②確定時に入力履歴を終了し、文書側の
  `FileTabDocument` 専用 `UndoManager` に「確定前後の draft」を 1 件登録 ③非編集中の ⌘Z は表示中の文書の確定済み置換を取り消す
  （`FileTabView` が `undoManager` として文書のものを返す）④新しいブロック編集は新しい入力履歴で始める。文書の undo/redo の後は再分割する。
- 編集欄は**最大高さ付きの内部スクロール**（`CodeTextEditor` は内部スクロール方式で、内容に合わせて外へ高さを返さないため）。

**表示 `MarkdownBlockEditor`**

- `ScrollView { LazyVStack { ForEach(blocks) } }`。ホバーで薄い背景、クリックで編集開始。リンク上のクリックはリンクを優先する。
- ↑↓ でブロック移動、Return で編集開始。
- テキスト選択はブロック内のみ（ブロックをまたぐ選択・コピーはソース表示で行う。第 1 版の制限として明記）。
- **アクセシビリティ**: 各ブロックに「編集」アクセシビリティアクション。操作説明は hint に（label に連結しない）。見出しには見出し属性。
  リンク・コード・表/リストの子要素はブロック 1 つへ統合しない。編集開始で入力欄へ、確定で元ブロックへフォーカスを戻す。

**モード切替**: 帯に「レンダリング / ソース」。状態は `FileTabDocument` の非永続プロパティ `presentation`。`ChildTab` には持たせない。

ソース表示（Markdown・HTML を含む）と Markdown ブロック編集欄の色付けは、[シンタックスハイライト仕様](syntax-highlighting.md) に従う。

### 3.5 HTML のレンダリング表示

**方針**: 閲覧専用のプレビュー＋ソース編集。HTML を表示状態のまま編集すると、保存時に HTML が組み立て直されて原文が崩れる。
**HTML は「信頼していない文書」として扱う**（エージェントやリポジトリが生成したもの）。

**`HTMLPreviewView`（`NSViewRepresentable` で `WKWebView` を包む）**

- 設定: `defaultWebpagePreferences.allowsContentJavaScript = false`（**常に**。切り替えトグルは作らない）、
  リンクのホバー表示（§3.8）は、アプリの `WKUserScript` を専用の `WKContentWorld` で動かして `a[href]` の mouseover だけを拾う。
  ページの world からはそのメッセージハンドラが見えない。非公開の WebKit API は使わない（2026-10-03 PM 判断）、
  `websiteDataStore = .nonPersistent()`、`setURLSchemeHandler(WorktreeSchemeHandler, forURLScheme: "phlox-worktree")`。
- **外部通信の遮断**: `WKContentRuleListStore` で「`phlox-worktree` 以外へのページ由来の要求をすべて block」するルールを
  コンパイルし、**コンパイル完了後に初回の読み込み**をする。失敗したらプレビューを出さず、ソース表示＋理由にする。
  （JS 無効でも `<img src="https://…">`・CSS・フォントは通信するため。外部 CSS を許すと、表示中の文書の DOM にある値を
  属性セレクタ経由で外へ送れる研究例があるので、第 1 版では外部リソースを許可する手段も作らない。）
- 表示: `phlox-worktree://local/<相対パス>` を読み込む。メイン文書の要求には**ディスクではなく draft**を返す（読込開始時の draft の版を固定）。
  `/` で始まるパスは worktree ルート基準。`<base>` は特別扱いせず、WebKit が解決した後の URL を検査する。
- `WorktreeSchemeHandler`: `@MainActor` で `start`・`stop`・応答を直列に扱い、task ごとに停止済みかを応答直前に確認する
  （停止済み task へ応答すると例外になるため）。GET のみ。percent-decode は 1 回だけ行い、NUL・不正な符号化・`..` は拒否。
  §3.2 (a) と同じ包含確認を通った通常ファイルだけ返す。MIME は拡張子から `UTType`。
- 遷移（`decidePolicyFor`）: サブフレームは worktree 内（`phlox-worktree`）だけ許可。メインフレームは初回の読み込みとページ内
  アンカー以外をすべてキャンセルし、**ユーザーがリンクをクリックした場合（`navigationType == .linkActivated`）に限り**
  worktree 内の `.html`/`.md` → `openFileTab`、`http(s)` → 既定ブラウザ。`target="_blank"`・フォーム送信・新規ウィンドウは開かない。
- WebContent プロセスが終了したら「表示が停止しました。再読込」を出す。
- WKWebView は NSView なので、重ね表示のインスペクタ（SwiftUI の overlay）が隠れないかを実画面で確認する（未検証）。
- 依存: `WebKit` はシステムフレームワーク。`DashboardFeature` のファイルタブだけが import する。

### 3.6 未保存の確認（アプリ終了・ウィンドウを閉じる）

- 下書きは**ウィンドウ間で共有しない**（`FileTabDocuments` はウィンドウごとのまま）。App レベルに弱参照の登録簿を置き、
  各ウィンドウの `FileTabDocuments` を登録する。
- **ウィンドウを閉じる**: `windowShouldClose(_:)` でそのウィンドウの `hasUnsavedChanges` を集め、あれば
  「保存せず閉じる／キャンセル」を出す。承認後に文書を失効させ（下記）、進行中の保存の完了を待ってから閉じる。
- **アプリ終了**: `applicationShouldTerminate` で**`cleanupGuard.beginCleanup()` より前に**全ウィンドウの未保存を集め、
  あれば確認する（一括保存は競合ダイアログが絡むため第 1 版では出さない）。承認後だけ既存の終了処理へ進む。
  キャンセルなら `.terminateCancel` を返し、ガードは開始しない。確認中の再要求は 1 つにまとめ、ウィンドウ単位の確認と重複表示しない。
- **複数ウィンドウにまたがる確認**: 下書きはウィンドウごとだが、セッションは全ウィンドウで共有されている。セッション削除・作業ディレクトリ変更・
  プロジェクト移動の確認では、操作したウィンドウだけでなく**登録簿から全ウィンドウの未保存を集めて**示す（現行の削除確認は操作元のウィンドウの
  下書きだけを見ている: `DashboardView.swift:95`）。子タブを閉じるときは、その文書に未保存があれば確認し、承認後に進行中の保存を待ってから破棄する。
- **文書の失効**: セッション削除・作業ディレクトリ変更・プロジェクト移動・ウィンドウを閉じるの承認後、旧文書に `invalidated` を立ててから
  登録を外す。失効した文書は保存・確定・undo を拒否する。進行中の保存は変更完了前に終わるのを待つ。保存は文書ごとに直列化する。
  `FileTabDocuments.document(for:)` の自動置換（作業ディレクトリが違えば作り直す）は、旧文書が未保存なら行わない（最後の防御）。
  削除などの副作用は 1 か所で 1 回だけ実行し、各ウィンドウの監視処理に分散させない。
- 強制終了・SIGKILL・クラッシュ時の下書き保護は保証しない。

### 3.7 ショートカット

| 操作 | キー | 備考 |
|---|---|---|
| ファイルツリーを表示 | ⌃⌘B | インスペクタを開き `.files` を選ぶ（`showFilesInInspector()`）。2026-10-02 時点で `App/`・`Packages/*/Sources` に割り当てなし |
| レンダリング / ソース切替 | ⌃⌘M（ファイルタブ内） | 同上 |

### 3.8 UI の細部（Claude Design のモックで確定。2026-10-02）

> 見た目と文言は見本を正とする。この節は見本では表せない挙動だけを書く。対応状況は `delivery/0039-design-alignment-worklog.md` に記録する。端末名の省略はシミュレーター側 §3.8 に従い、他の文言・版・状態を縮めても収まらない場合の最後の手段とする。

見た目の正本は `specs/ClaudeDesign/1〜6 *.dc.html`（同じフォルダの `support.js` と一緒にブラウザで開く）。ここには挙動に関わるものだけを書く。

**ファイルツリー（モック 2）**
- 上部のブランチ行は高さを固定し、取得に失敗しても行を残す（取得できたときに下がずれない）。detached HEAD は「detached HEAD」の文字とコミット短縮名を並べる（色だけに頼らない）。
- フォルダ行の Return は開閉（ファイル行の Return は開く）。
- 開けない行（ルート外を指す symlink）は薄く表示し、ホバーで解決先（`~/` 表記）を出す。VoiceOver には「開けません」と読ませる。
- フォルダの読込エラーは、行に丸に「!」・「読み込めませんでした」・理由を面付きで出す（見本 2h。専用の再試行ボタンは置かない。上部の「更新」かフォルダの開き直しで読み直す）。ルート外のリンクをクリックしたときは、帯に開けない理由を折り返して全文を出す。
- 行の読み上げは「名前、種類、レベル n、展開／折りたたみ」。ツリー領域の内側にフォーカスの輪を出す。
- ボタン名は「更新」（HTML 表示の「再読込」とは別物）。

**ファイルタブの帯（モック 3）**
- ソースの字句色は `syntax-highlighting.md` §4 に従い、見本の行番号・20pt 行間・余白を維持する。ダーク配色は Xcode の既定テーマと既存コード表示に揃え、見本の plain 表示から色付けへ更新する（[シンタックス仕様 §4 のダーク色の判断](syntax-highlighting.md)）。
- 「レンダリング / ソース」の切り替えは `.md`/`.markdown`/`.html`/`.htm` のときだけ出す。切り替えられない状態（大きすぎてソース固定・ブロックの確定待ち・HTML の遮断準備の失敗）では、項目を**隠さず無効のまま残し**、帯に理由を出す。
- ⌃⌘M は、対象外のファイル・開けないファイル・切り替えられない状態では何もしない。
- 狭い幅では、ファイルパス（先頭側を省略）→ 文言 → アイコン化（「Aa」「</>」）の順に縮める。アイコン化したときも読み上げ名は「レンダリング」「ソース」。
- 320pt の帯の切り替えは、見本 1e と 3j の食い違いについて 3j を採用する。
- 子タブ列の作業フォルダのパスは幅に応じて先に縮め、最小幅320ptでは選択タブと追加ボタンを優先する。ブロックの確定失敗時に薄くするのは「ソース」だけとし、保存を試みたときは帯の理由を強調する。
- 広幅では追加ボタンを最後のタブ直後に置き、パスは右端へ寄せる。タブ全部が収まらない狭幅では、選択タブを残すためタブだけのスクロール領域の右直後へ追加ボタンを固定する。
- 表示切り替えの読み上げ名は「表示」、ショートカットは補足説明（description）に分ける。保存ボタンも「保存」と「⌘S」を分ける。

**マークダウンのブロック編集（モック 4）**
- 確定の手がかりは「⌘Return・Esc・ブロックの外をクリックで確定」。
- 確定できないときの理由文は「文書が先に変わったため確定できません」（外部でのファイル変更とは別。外部変更は保存時の競合ダイアログが扱う）。
- 編集中の 1 ブロックだけをアクセントの枠で示す。参照定義と空行は編集中にだけ見える。
- 参照リンクにホバーすると、解決したリンク先を出す。リンクのホバー時は左下に行き先（「ファイルタブで開く」「ブラウザで開く」「開きません」）を出す（HTML 表示も同じ）。
- ブロックをまたいで選択しようとしたときは、ソース表示で行う旨を控えめに案内する。
- ブロック内の文字選択は §3.4 の要件を維持する。「Return で編集」の案内は選択の輪の外の右上に置き、選択中のブロックの前に20pt確保して直前のコードブロックへ重ねない。案内自身は入力を受け取らない。
- 段落内の単一改行は CommonMark の soft break として同じ段落内に詰めて折り返す。表示文字が CJK 同士（ハングルを除く）なら空白を入れず、英語・韓国語は空白でつなぎ、明示改行は維持する。表示だけを変え、原文のバイト保存（NFR-1）は変えない。

**HTML の表示（モック 5）**
- 帯に「閲覧のみ」と「再読込」ボタンを出す。
- 遮断の表示は固定の文言「外部の読み込みを止めています」（件数・URL の一覧は出さない。WebKit の遮断の仕組みが返さないため）。クリックで説明のポップオーバー（「このページが出す外部への要求と、ページのスクリプトは止めています」）。
- 遮断の準備に失敗したらソース表示に固定し、「レンダリング」を無効のまま残す。
- フォームの送信は何も起きない。

**未保存の確認（モック 6）**
- ウィンドウを閉じるときはシート、アプリ終了はアラート。ボタンは「キャンセル」（既定。縦並びなら一番上）と「保存せず閉じる／保存せず終了」。アイコンは Phlox のアプリアイコン。
- 破棄のボタンは macOS 標準の破棄表示（`NSAlert` の `hasDestructiveAction`）をそのまま使う。独自の配色でコントラストを上げることはしない（ユーザー決定 2026-10-02）。
- 一覧は合計 5 件まで出し、残りは「ほか N 件」。ウィンドウが 2 つ以上のときだけウィンドウ別の見出し（「ウィンドウ 1 · <名前>」）を付け、残りを「ほか N 件（M ウィンドウ）」とする（見本 6a・6d。2026-10-03 改訂）。見出しだけで中身が空になるウィンドウは作らない。
- 未確定のブロック編集を含むファイルには「編集中」のタグを付け、本文にも 1 文添える。
- 一覧の2行目は同名ファイルのフォルダを判別できる幅を確保する。複数ウィンドウの見出しの下ではプロジェクト名を繰り返さない。
- 確認中に ⌘Q を繰り返しても、ダイアログは 1 つだけ。

## 4. 既存機能との互換性

| 既存機能 | 影響 | 根拠 |
|---|---|---|
| ⌘P でファイルを開く | **変わる**: 共通ターミナル表示中でもファイルタブが前に出る（既存の不足の修正） | §3.2 (d) |
| worktree 外を指す symlink のファイル | **変わる**: 読み書きとも拒否し、解決先と「Finder で表示」を出す | §3.2 (a) |
| 巨大ファイル・UTF-8 として読めるバイナリ | **変わる**: 読み込まず理由を表示（非 UTF-8 は従来どおり「開けません」） | §3.2 (c) |
| BOM 付き UTF-8 ファイルの保存 | **変わる**: BOM を保持する | §3.2 (c) |
| 未保存・競合判定 | **変わる**: バイト比較になり、正規等価な変更も検出する | §3.2 (c) |
| アプリ終了・ウィンドウを閉じる | **変わる**: 未保存があれば確認が出る | §3.6 |
| 変更タブ（diff・コミット／push／PR） | 不変 | 呼び方を変えない |
| 保存・⌘S・競合ダイアログ・「別セッションが書き換えた」表示 | 挙動は同じ（比較方法だけ変わる） | §3.2 |
| タブの永続化 `phlox.sessionTabs.v1` | 形式不変 | `ChildTab` を変えない |
| インスペクタ幅・重ね表示・⌃⌘I・使用量チップ | 不変 | 新ペインを作らない |
| チャットのマークダウン描画 | 不変 | 既存の init は変えない |
| `.html` を開いたとき | **変わる**: 既定がレンダリング表示 | §3.5 |

## 5. 出荷単位と実装順（各段で既存テスト全数 green）

1. **基盤修正（§3.2・§3.6）**: symlink 包含確認・ルート固定・Data 読み書きと BOM・読み込み状態 enum・`openFileTab` 共通化・
   終了／ウィンドウを閉じる確認・文書の失効。**単独で出荷し、既存のファイル操作の回帰を検証する。**
2. **ファイルツリー（§3.3）**: Loader・Rows・Model・`InspectorTab.files`・View・⌃⌘B。
3. **HTML 表示（§3.5）**: 遮断ルール・スキームハンドラ・遷移判定・`HTMLPreviewView`。
4. **マークダウンのブロック編集（§3.4）**: `swift-cmark` 明示・`MarkdownBlocks`・`RichMarkdownView(source:openURL:)`・編集状態・
   `MarkdownBlockEditor`・アクセシビリティ（最も難しいので最後）。
5. 実画面確認 → ADR 起票 → `architecture/` へ蒸留、古い terminal-editor-panels 文書の扱いを決める。

## 6. テスト計画

凍結受け入れテスト（`.claude/verify.sh` が無改変を検査するファイル）は編集しない。新規テストを足す。

| テスト（新規） | 固定する性質 |
|---|---|
| `WorkingTreeContainmentTests`（一時ディレクトリ） | ルート外を指すファイル/ディレクトリ symlink の読み書き拒否／ルート内 symlink は可／通常ファイル以外の拒否／ルート固定で別ルートに書かない |
| `FileTabDocumentBytesTests` | 合成/分解表現の違いを dirty・競合として検出／BOM の保持／CRLF・混在改行・末尾改行なしの往復一致／1 MB 超・NUL 入りを読まない |
| `FileTabDocumentLifecycleTests` | 失効後の保存・確定・undo の拒否／未保存の旧文書を自動置換しない／保存の直列化 |
| `TerminationConfirmationTests` | 終了→キャンセル→編集継続→再度終了／未確定の編集→ウィンドウを閉じる→キャンセル→編集復元 |
| `MarkdownBlocksTests` | 区間の連結＝原文（バイト一致）・全行被覆（見出し・入れ子リスト・表・空行を含むフェンス・閉じていないフェンス・HTML・参照定義（ブロック間・段落内・重複）・front matter・空文書・定義のみ・CRLF）／描画用 Markdown で参照リンク先が文書全体の規則どおり／1 区間の置換で他区間のバイト不変 |
| `MarkdownRenderParityTests` | 小さな固定文書で、全体描画とブロック描画の構造（リンク先・表のセルと配置・リスト・強調・コード内容）が一致 |
| `ActiveBlockEditTests` | 確定は 1 回だけ／`baseVersion` 不一致で置換しない／撤去後に戻ると復元／undo 契約の 4 項目／`編集→改行追加→確定→保存→undo→redo` |
| `OpenFileTabTests` | 要求時のルートで開く／`A で開く要求→作業場所を B に変更→要求完了` で B の同名ファイルを開かない／単体表示への切替と共通ターミナル解除／既に開いていれば前に出す／分割指定で右の区画に出す |
| `CrossWindowDraftTests` | B だけに未保存がある状態で A からセッションを削除すると、確認に B のファイルが出る／子タブを閉じる確認と保存待ち |
| `MarkdownLinkRoutingTests` | 文書の位置からの相対リンク解決／ルート外・対象外拡張子は開かない／http(s) は外部へ |
| `PresentationLockTests` | 2,000 ブロック・500 KB の境界でソース固定になる／固定中は ⌃⌘M が何もしない |
| `HTMLPreviewRefreshTests` | ソースから戻る・再読込・保存のたびに最新の draft が表示される |
| `FileTreeModelTests` | 開いている行の強調（FR-5）／同じルートで展開状態を保つ（FR-6）／更新・展開・保存時の再読込（FR-7） |
| `FileTreeRowsTests` / `FileTreeLoaderTests` | 平坦化・並び順／`.git` 除外／symlink ディレクトリを展開しない／同一フォルダ集約・古い世代の破棄／5,000 件上限 |
| `WorktreeSchemeHandlerTests` | 包含確認／`..`・NUL・不正符号化・二重エンコードの拒否／GET 以外の拒否／メイン文書は draft／停止後に応答しない（`読込開始→停止→旧読込完了`） |
| `HTMLNavigationPolicyTests`（純関数） | ユーザーのリンククリックだけ外部へ／サブフレームは worktree 内のみ／新規ウィンドウ・フォーム送信を開かない |
| `HTMLNetworkIsolationTests`（実行時） | ローカルの HTTP 受信先を立て、画像・CSS・フォント・iframe・`@import` の要求が届かないこと、worktree 内のリソースは表示されることを対で確認／遮断ルール失敗時に読み込まない |
| ランタイム描画テスト（`NSHostingView`、ADR 0090 の教訓） | 狭幅（重ね表示）でもツリーが描画される |
| 実画面（`swift-testing-and-perf`） | 日本語変換中に保存・切替して戻ると再編集できる／ブロック編集の位置・重なり・選択／重ね表示のインスペクタと WebView の前後関係 |
| XCUITest | ⌃⌘B → 行クリックでファイルタブ → `.md` のブロック編集 → ⌘S／`.html` のレンダリング → ソース切替 |

accessibilityIdentifier: `inspector-files`・`file-tree`・`file-tree-row-<path>`・`file-tab-presentation`・`markdown-block-<index>`。

検証コマンド: `swift test --package-path macos/Packages/DashboardFeature`・`.../SessionFeature`（全数）、`xcodebuild build`、
上記 XCUITest と実画面確認（Debug 版を別インスタンスで起動。稼働中のリリース版は終了させない）。

## 7. スコープ外（第 1 版でやらないこと）

| 項目 | 理由 | 足すときの道筋 |
|---|---|---|
| ファイル監視による自動更新 | 既存機能も手動更新の方針 | `FSEventStream` をルート単位で持ち、展開中フォルダだけ再読込 |
| ファイル・フォルダの作成／名前変更／削除／移動 | 依頼外。エージェントが作業中の場所で破壊的操作になる | 右クリックメニュー。削除はゴミ箱へ・確認付き |
| Git 状態の色付け・.gitignore 対象の薄表示 | 依頼外 | `WorkingTreeService.changes()` の結果を行に重ねる |
| worktree 外を指す symlink の閲覧 | 包含確認と矛盾し、HTML のサブリソースにも漏れる | 明示操作による別の読み取り経路（HTML には使わない） |
| マークダウンのブロックをまたぐ選択・コピー | ブロック単位描画の制約 | ソース表示で行う |
| マークダウン内の相対パス画像 | worktree 基準の画像読み込みが要る | MarkdownUI の `ImageProvider` を差し込み、包含確認を通す |
| タスクリストのクリック切替 | 依頼外 | 区間が分かるので `[ ]`↔`[x]` の置換で実装できる |
| 書式ツールバー・Word 風の完全 WYSIWYG | ユーザー決定でブロック編集を採用 | §8 |
| HTML の JavaScript 実行・外部リソースの読み込み | 信頼していない文書から情報が漏れる経路になる（§3.5） | 許可する場合は、表示文書の情報が外部へ送られ得ることを明示した上で別途判断 |
| HTML をレンダリング状態のまま編集 | 保存時に原文が組み立て直されて壊れる | 要素単位で原文を差し替える方式を別途検討 |
| 終了時の一括保存 | 競合ダイアログとの組み合わせが複雑 | 文書ごとに順に保存し、競合が出たら中断 |
| 強制終了・クラッシュ時の下書き保護 | 自動保存の仕組みが別途必要 | 定期的に下書きを退避 |
| ツリー展開状態の永続化 | 必要性未確認 | `@SceneStorage` にルート別で保存 |

## 8. 設計判断（実装着手時に ADR 化する）

1. **ツリーはインスペクタの新タブ**（新ペインは棄却）: 幅・重ね表示・開閉を流用でき、`PaneWidthPolicy` を変えずに済む。代償は最大 340pt の幅。
2. **開く先は既存のファイルタブ**（専用エディタは棄却）: 保存・競合・未保存確認を二重実装しない。
3. **マークダウンはブロック単位編集・原文が正本**（ユーザー決定 2026-10-02）。棄却: WKWebView＋JS エディタ（保存で記法が書き換わる）、
   属性付きテキストから再生成（表・入れ子・front matter が失われる）、左右並列（要望を満たさない）。
4. **描画は文書全体のパースからノード単位で Markdown を再出力**（ブロックの原文を個別に描画する案は棄却）: 個別に描画すると、
   別ブロックにある参照定義が解決できない・閉じていないフェンスに定義が吸い込まれる・重複定義の優先順位が変わる、という反例がある（レビューで判明）。
5. **パスの安全性は入口ではなく共通の読み書き経路で保証**: 開いた後に symlink が差し替えられると入口の確認は失効するため。
6. **未保存・競合はバイト比較**: Swift の `String ==` は Unicode 正規等価で比較し、バイトの違いを見逃すため。
7. **HTML は JS 常時無効・外部通信常時遮断・独自スキームで worktree 内だけ配信**（`file://` 読み込みと外部リソース許可は棄却）。
8. **下書きはウィンドウ間で共有しない**: 共有すると複数ウィンドウからの同時編集に編集の所有権が必要になる。終了確認は登録簿で集める。

## 9. 未決事項

| 論点 | 事実 | 決め方 |
|---|---|---|
| ~~左右分割とインスペクタの幅~~（**解決済み**: 現行の挙動を維持） | 現行コードは、分割中でも中央の幅が 641pt 未満なら**操作中のタブだけを表示**する（`SessionTabsContainer.swift` の `minimumPaneWidth * 2 + 1`）。1200pt・左 260pt・インスペクタ 300pt では中央は 638pt なので、319.5pt の区画が並ぶことは無く、操作中のタブだけになる。モック 1e の「区画が 320pt を割る」は誤り | 既存の縮退表示を維持する（NFR-6 と整合。`PaneWidthPolicy` は変えない） |
| 重ね表示のインスペクタからファイルを開いたとき | カードを開いたままにするか閉じるか、設計書は決めていない（モック 1 の論点 3） | 実画面で試して決める。既定は「開いたまま」（FR-3 に閉じる挙動は無い） |
| 重ね表示のインスペクタと WKWebView・端末画面（NSView）の前後関係 | 未検証 | 実画面で確認する（§3.5） |
