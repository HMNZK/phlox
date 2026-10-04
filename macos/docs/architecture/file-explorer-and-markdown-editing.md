---
status: active
last-verified: 2026-10-04
---

# ファイルツリー・マークダウンのブロック編集・HTML 表示の現行構成

> **このファイルの役割**: 右サイドバーのファイルツリー、ファイルタブ（`FileTabDocument`）、マークダウンのブロック編集、HTML のレンダリング表示、
> 未保存の確認の**現行構造**。コード（`macos/Packages/DashboardFeature/Sources/DashboardFeature/{Files,Tabs}` ほか）で確かめた事実だけを書く。
> **書かないもの**: なぜこの構成にしたか（→ [ADR 0178](../adr/0178-file-explorer-markdown-and-html-in-file-tabs.md)）、
> 満たすべき要件・テスト計画（→ [specs/file-explorer-and-markdown-editing.md](../specs/file-explorer-and-markdown-editing.md)）。
> 旧「trailing ドロワー」構成の文書は [terminal-editor-panels.md](terminal-editor-panels.md)（一部が現行と食い違う。同文書の冒頭注記を参照）。

## 全体像

```
InspectorView（UsageSidebarView.swift）── [セッション | ファイル | 使用量]   AppRouter.inspectorTab: InspectorTab
        └ .files: FileTreeInspectorView ── FileTreeModel（ルートごと） ── FileTreeLoader（actor）
                          │ 行クリック・Return・右クリック「右に分割して開く」
                          ▼
FileTabDocuments.openFileTab(sessionID:root:relativePath:split:router:requestedWorkingDirectory:currentWorkingDirectory:)
   ← ⌘P（NSOpenPanel）・変更タブ・ファイルツリー・マークダウン/HTML のリンク が共通で通る
                          ▼
子タブ ChildTab.file(相対パス) ── RestoredFileTabView → FileTabUndoScope → FileTabView ── FileTabDocument
     ├─ ソース表示:                   CodeTextEditor（NSTextView）
     ├─ レンダリング表示（.md/.markdown）: MarkdownBlockEditor ── MarkdownBlocks.analyze ── RichMarkdownView(source:openURL:…)
     └─ レンダリング表示（.html/.htm）:    HTMLPreviewView（WKWebView）── WorktreeSchemeHandler（phlox-worktree://local/<相対パス>）
読み書き: WorkingTreeService(repositoryRoot:fixedRoot: true)   終了・ウィンドウを閉じる確認: FileTabDocumentRegistry.shared
```

ソース表示の色付けは [シンタックスハイライト仕様](../specs/syntax-highlighting.md) と [ADR 0180](../adr/0180-syntax-highlighting-with-in-house-lexer.md) に従う。

背景計算の範囲操作用テキストは UTF-16 から `NSString` の実体を一度作る。行境界は同じ UTF-16 配列を前へ走査して使い回し、CRLF と Unicode の改行も保つ。Swift 文字列への橋渡しと Foundation の範囲操作を行ごとに繰り返す費用を避け、原文は維持する。

埋め込み言語の解析結果は `ChatSyntaxLexer` 内で UTF-8 範囲のまま反映し、最外部でだけ文字列トークンへ変換する。入れ子の文字列配列を作って長さだけ読み直す中間処理を省く。

## ソースの色付け

- `FileTabView` は文書のパスを `CodeTextEditor` へ渡す。`ChatRenderKit.ChatCodeTokenizer.language(for:code:)` がファイル名・拡張子・shebang・plain の順で種類を決め、一度構築した `ChatSyntaxRules` の言語別データと `ChatSyntaxLexer` の共有走査を使う。
- `CodeSyntaxHighlights` は全文の字句計算を背景タスクで行う。編集通知からは 50 ms 待ってまとめ、取り消したタスクと世代が古い結果を破棄する。前回の適用成功結果と背景で比較し、種類が変わった範囲と編集段落を UTF-16 の範囲で渡して、`NSLayoutManager` の一時的な前景属性を分割して反映する。途中取消・種類やテーマの変更では全範囲を反映する。段落属性は維持し、plain の一時前景は除去する。Markdown ソースの ATX 見出しだけは保存用テキストストレージのフォント属性を等幅の semibold にし、本文へ戻った範囲は通常の太さへ戻す。フォント変更はバッチごとに `beginEditing` / `endEditing` でまとめる。同じ行のトークンは行範囲を使い回す。
- 待機中の編集範囲は挿入・削除に合わせて移動・統合する。削除した文字を戻した後で別段落を編集しても、途中の編集で消えた一時色を復元する。複数範囲の置換は全範囲を反映する。
- 色は `SessionFeature.CodeSyntaxColor` が既存の `DSColor` へ割り当てる。DesignSystem は字句解析へ依存しない。チャットも同じ割り当てを使い、チャット固有の型・呼び出し・メンバーの色とキーワードの太字を維持する。
- marked text の間は本文同期と属性更新を保留する。確定後に現在の本文を再計算する。属性更新は undo へ登録せず、選択・スクロール・typingAttributes を保つ。本文色は初回に動的な `NSColor` を設定し、テーマ変更時はロックで保護した解決先の色と描画を更新する。色の追従では全文の保存属性を更新しない。見出しのフォント変更はバッチを閉じてから選択と入力属性を復元する。文書の draft・version・保存バイト列は色付け処理から変更しない。
- Markdown のブロック編集は front matter を含む全ブロックを Markdown として同じ編集欄へ渡す。フェンス内部と先頭 front matter の YAML への切替は Markdown の共有字句規則で処理する。
- 1 行が 10,000 UTF-16 単位を超える文書と編集上限を超える本文は plain にする。ライト・ダークを含むテーマの変更は色を解決し直す。検証結果と性能値は [作業記録 0040](../delivery/0040-syntax-highlighting-worklog.md) に記録する。

## ファイルツリー

| 型（`DashboardFeature/Files/`） | 種別 | 役割 |
|---|---|---|
| `FileTreeInspectorView`（`FileTreeView.swift`） | View | 選択中セッションの `rawWorkspacePath` から `FileTabOpening.root(for:)`（Git ルート、無ければ作業ディレクトリ。symlink 解決済み）を求め、`FileTreeModel` を取得・登録して `refresh()` する。セッション未選択時は空状態の文言、ルート解決中は `ProgressView`。accessibilityIdentifier `inspector-files` |
| `FileTreeView` | View | ヘッダー（ルートのパス・ブランチ名・更新ボタン）と `ScrollView` + `LazyVStack`。選択行 `selectedPath` はこの View の `@State`。↑↓（表示中の行間を移動）・→（展開／最初の子へ）・←（折りたたみ／親へ）・Return（フォルダは開閉、ファイルは開く）は `onKeyPress` から自前のキー処理へ渡す。右クリックは「右に分割して開く」（開ける行のみ）・「Finder で表示」・「パスをコピー」。識別子 `file-tree`・`file-tree-row-<相対パス>` |
| `FileTreeModel` | `@MainActor @Observable` | `root`・`childrenByDir`・`expanded`・`errorsByDir`・`omittedByDir`・`loading`・`branch`。`DashboardView` の `@State fileTreeModels: [ルートパス: FileTreeModel]`（ウィンドウごと・非永続）に置く。`expand`・`collapse`・`refresh`（展開中フォルダとルートを並行再読込し、ブランチ名も取り直す）・`fileSaved`（保存したファイルの親フォルダを再読込）・`load`（フォルダごとの世代 UUID で古い結果を捨てる） |
| `FileTreeLoader` | `actor` | `children(of:refresh:)` を `Task.detached` で実行する。読込中の同一フォルダへの要求は同じ Task に集約し、`refresh: true` の要求は置き換えて、置き換えられた側は `nil` を返す |
| `FileTreeRows` | 純関数群 | `visibleRows`（深さつき平坦化）・`action(for:key:rows:expanded:)`（キー操作の解釈）・`visibleSelection`・`openPath`（単体表示かつ共通ターミナル非選択のときだけ、操作中のファイルタブのパスを返す） |
| `FileTreeEntry` | 値型 | `Kind` は `directory` / `file` / `symlinkToDirectory` / `symlinkOutsideRoot` / `symlinkToFile` / `unavailable`。展開できるのは `directory` だけ、開けるのは `file` と `symlinkToFile` だけ |

- `FileTreeLoader.readDirectory`: `contentsOfDirectory` の結果から `.git` と `.DS_Store` を除く。並びはフォルダ先、次に `localizedStandardCompare`（同順位はバイト列順）。
  各行は `WorkingTreeService.containedURL` でルート内か確認し、ルート外を指す symlink は `symlinkOutsideRoot`（解決先つき）にする。
  読めない・通常ファイルでもフォルダでもない行は `unavailable`（理由つき）。展開対象のパスのどこかの祖先が symlink なら読み込まずエラーにする。
- **1 フォルダの上限は 5,000 件**。超えた分は捨て、残り件数を `omittedByDir` に持ち、「ほか N 件（⌘P で開けます）」と表示する。
- ブランチ名は `WorkingTreeService.branchLabel()`: ブランチ名／`detached HEAD <短縮コミット>`／`Git 管理外`／取得失敗は空文字。
- 再読込の契機: 更新ボタン・フォルダ展開・ファイル保存成功（`Notification.Name.fileTreeFileSaved` を `DashboardView` が受けて `FileTreeModel.fileSaved`）・「ファイル」タブの表示時（`FileTreeInspectorView` の `.task(id: セッション ID + 作業ディレクトリ)`）。ファイル監視は無い。
- ツリー自体はディスクへ書き込まない。
- ショートカット: ⌃⌘B（`PhloxApp.swift` のメニュー項目「ファイルツリー」）→ `AppRouter.showFilesInInspector()`（`inspectorTab = .files`・`inspectorVisible = true`）。

## 開く共通関数

`FileTabDocuments.openFileTab`（`Tabs/FileTabOpening.swift`）は、次の場合に何もせず `false` を返す: 要求時の作業ディレクトリが現在のセッションの `rawWorkspacePath` と違う／そのセッションが作業場所の変更中（`FileTabDocumentRegistry.isChangingSession`）／生成した文書のルートが要求と違う・失効済み。
通れば `router.viewMode = .single`、`router.commonTerminalSelected = false` にして、`router.tabs.updateLayout` で `ChildTab.file(相対パス)` を開く（`split: true` なら右の区画へ `splitRight`）。
ルートは要求時に固定して渡し、`FileTabDocuments.document(for:path:root:)` で文書を作る（セッション × 相対パスごとに 1 つ。既存文書はルートが同じか、未保存・保存中なら再利用）。

## ファイルアクセス（`WorkingTreeService`）

- `WorkingTreeService(repositoryRoot:fixedRoot:)`。`fixedRoot: true` は読み書きのたびに `git rev-parse` でルートを再解決せず、渡されたルート（symlink 解決済み）に固定する。ファイルタブ・ツリー・HTML 配信はすべてこのモードで使う。変更タブ側は従来どおり `fixedRoot: false`。
- 共通経路 `accessibleFileURL`: ルートが存在するディレクトリであること（無ければ `missingRoot`）→ `relativeURL`（絶対パス・NUL・空要素・`.`・`..` を拒否）→ `containedURL`（親と末尾を `resolvingSymlinksInPath()` した実パスがルート配下であること。違えば `outsideRoot(実パス)`）→ 通常ファイルであること（違えば `notRegularFile`）。`fileData`・`resourceData`・`save`・`absolutePath` がこれを通る。
- 読み込み `fileData`: サイズ 1,000,000 バイト（`WorkingTreeText.maximumEditableFileSize`）超は `tooLarge`。`WorkingTreeText.decode` は先頭 8,192 バイトに NUL があれば `binary`、先頭 `EF BB BF` を BOM として分離し、残りを厳密な UTF-8 として復号する（失敗は `invalidUTF8`）。
- 保存 `save(path:data:expectedDiskBytes:)`: `expectedDiskBytes` が非 nil なら現在のディスクの `Data` と一致するときだけ書き、不一致・読めない・消えている場合は `.conflict`。`nil`（上書き）で保存先が消えていれば、親フォルダがルート内にある場合に作り直す。書き込みは `.atomic`。
- HTML の配信用 `resourceData`: 上限 32 MiB（`maximumHTMLResourceSize`）。

## `FileTabDocument`（draft が唯一の正本）

- 保持するもの: `draft`（現在の本文）・`loadedDiskBytes`（最後に読んだ／書いたディスクのバイト列）・`bom`・`version`（draft が変わるたびに +1）・`root`・`path`・`loadState`・`presentation`・`activeBlockEdit`。
- `LoadState`: `unloaded` / `loading` / `loaded` / `tooLarge` / `binary` / `loadFailed` / `outsideRoot(解決先)`。`FileTabView` は `tooLarge`・`binary` に「既定のアプリで開く」、`outsideRoot` に「Finder で表示」を出す。
- `isDirty` = `bom + draft の UTF-8` ≠ `loadedDiskBytes`（バイト比較）。`hasUnsavedChanges` = `isDirty` または未確定のブロック編集に差分がある。`draft` の setter はバイト単位で変わったときだけ `version` を進める。
- 保存 `enqueueSave`: 失効後は `DocumentError.invalidated`。ブロック編集の確定に失敗すれば `blockEditVersionMismatch`。保存は文書ごとに直列（前の保存の完了を待つ）で、成功したら `loadedDiskBytes` と基準時刻を更新し、HTML プレビューを再描画させ、`fileTreeFileSaved` を通知する。競合は `SaveResult.conflictDetected` で、`FileTabView` が上書き／キャンセルのダイアログを出す（上書きは `expectedDiskBytes: nil`）。
- 競合時の「別セッションが書き換えた」表示用に、`lastWriter(among:excluding:)` が他セッションのファイル変更記録を突き合わせる（時刻の許容幅 5 秒）。
- 失効 `invalidate()`: 未確定のブロック編集を捨て、undo 履歴を消し、以後の保存・確定・undo を拒否する。進行中の保存があれば、その完了後に `invalidated` になる。
- 既定の表示: `.md`/`.markdown`/`.html`/`.htm` は `.rendered`、それ以外は `.source`。`presentation` は非永続で、`ChildTab` には持たせない。
- ⌃⌘M（`FileTabView` の隠しボタン。フォーカス中のタブだけ有効）でレンダリング／ソースを切り替える。切り替えられない状態（読込前・失効・ブロック編集の確定失敗・マークダウンがソース固定・HTML の遮断準備が未完了または失敗）では何もしない。帯の「レンダリング」ボタンは無効のまま残る。

## マークダウンのブロック編集

**分割 `MarkdownBlocks.analyze(_:)`（`Files/MarkdownBlocks.swift`、純関数）**

- 文書を UTF-8 のバイト列として扱い、全体を 1 回 cmark-gfm でパースする（`CMARK_OPT_DEFAULT`。拡張は `autolink`・`strikethrough`・`tagfilter`・`tasklist`・`table`）。
- 先頭行が `---` で、後ろに別の `---` 行があれば、その範囲を `frontMatter` ブロックとして切り出し、残りだけをパースする。
- 最上位ノードごとに 1 ブロック。ブロックの範囲 `range`（バイト位置）は「ノードの開始行から次ノードの開始行の直前まで」で、空行・参照定義も含む。行の区切りは LF・CRLF・単独 CR。位置を持たないノード（表の前の段落など）は隣のブロックへ統合する。
- `MarkdownBlock.Kind` は `markdown` / `heading(level:)` / `frontMatter` / `raw` / `empty`。0 バイトの文書は `empty` 1 つ、ノードが無い文書（空白・参照定義のみ）は `raw` 1 つ。
- 描画用 Markdown `renderedMarkdown` は、文書全体で参照解決した後のノードを `MarkdownBlockContent.render`（`Files/MarkdownBlockContent.swift`、自前の出力器）で出力したもの。`cmark_render_commonmark` は使っていない。
- 検証: 全ブロックの連結が原文とバイト一致し重複・欠落がないこと（`coversSource`）。満たせない・解析に失敗した場合は文書全体を `raw` 1 ブロックにして `isSafe = false`（ソース表示に固定され、帯に「文書の区間を安全に解析できないためソース表示で編集してください」を出す）。
- ソース固定の条件（`markdownPresentationLocked`）: 本文が 500,000 バイトを超える／`isSafe == false`／ブロック数が 2,000 を超える。500,000 バイト以下では、解析結果をバージョンごとにキャッシュし、ソース表示中の編集は 300 ms 後に `Task.detached` で再解析する（レンダリング表示への切り替え時は即時）。
- 依存: `DashboardFeature/Package.swift` の `swift-cmark`（`exact: "0.8.0"`。products `cmark-gfm`・`cmark-gfm-extensions`）。

**編集状態**

- `ActiveBlockEdit { id, baseVersion, range, original, current }` を `FileTabDocument.activeBlockEdit` が持つ。draft への反映は確定時の 1 回だけ（`commitActiveBlockEdit`）。
- 確定は `baseVersion == version` のときだけ成功し、`range` のバイト区間を `current` で置き換えて draft を更新する。不一致なら置換せず `blockEditFailure =「文書が先に変わったため確定できません」`。失敗中はソースへの切り替えと保存を無効にする。復旧操作は `FileTabView` が本文上に出す「編集を破棄」（確定前の編集だけ破棄し、draft を保持）と「ソースで開く」（確定前の内容をクリップボードへコピーし、`openSourceDiscardingBlockEdit` で draft のソース表示へ戻る）。
- 確定の契機（`CodeTextEditor` / `CurrentLineTextView`）: Esc（keyCode 53）・⌘Return（keyCode 36 + ⌘）・`resignFirstResponder`・ブロック外のクリック（`NSEvent` のローカルモニター）。⌘S とモード切替は、先に入力欄の内容を `activeBlockEdit.current` へ同期してから確定する。
- undo: `FileTabDocument.undoManager`（`FileBlockUndoManager`）に、確定ごとに「確定前の draft」を 1 件登録（操作名「ブロック編集」）。編集中は文書の undo を受け付けない。`FileTabUndoScope`（`NSViewRepresentable`）が表示中の responder として `undoManager` を返し、⌘Z/⇧⌘Z をこの履歴へつなぐ。

**表示 `MarkdownBlockEditor`（`Tabs/MarkdownBlockEditor.swift`）**

- `ScrollView { LazyVStack }`。各ブロックは `RichMarkdownView(source:openURL:onLinkHover:hoveredLink:)`（SessionFeature。チャット用の前処理 `TranscriptMarkdownPresentation.prepare` を通さない init）とファイル専用の `fileMarkdownTheme` で描く。`frontMatter`・`raw` は等幅の原文表示、`empty` は「クリックして書き始める」。クリック・ドラッグは `MarkdownBlockSelectionObserver` からブロック編集／境界の案内へ渡す。文字上では既存 SelectionView が選択可能な文字部品へ mouseDown を同期転送し、tracking の終了を直接受け取る。tracking 中の境界は選択変更通知と tracking mode の 30ms タイマーで `window.mouseLocationOutsideOfEventStream` の位置参照から判定する。文字選択を維持し、選択範囲がある場合は編集クリックと扱わない。リンクは `openURL` を優先し、キーは同 observer の responder の `keyDown` から処理する。
- 追跡終了後の文字部品の `selectedRange().length > 0` なら編集を始めない。ダブルクリックで単語を選んだ場合も同じ。
- 編集中のブロックは `CodeTextEditor`（`blockEditID` つき）に置き換わる。高さは `min(200, max(54, 行数 × 18 + 16))`（末尾の空行は数えない）。
- 操作: ブロックのクリック／Return／アクセシビリティの「編集」で編集開始、↑↓でブロック間のフォーカス移動。ブロックをまたぐドラッグ選択を検出すると「ブロックをまたいで選ぶには、ソース表示に切り替えます（⌃⌘M）」を出す。識別子 `markdown-block-<index>`。
- リンク: `MarkdownLinkRouting.resolvedURL` が、`file://` はルート相対へ、スキームなしの相対リンクは文書の位置を基準に解決し（`..` でルートを出るもの・ホスト付きは拒否）、`phlox-worktree://local/<パス>` に直す。行き先の判定は `HTMLNavigationPolicy.linkDestination`: 拡張子が `md`/`markdown`/`html`/`htm` の worktree 内パス → ファイルタブで開く、`http`/`https`（ホストあり）→ `NSWorkspace` で既定ブラウザ、それ以外は何もしない。ファイルへのリンクは開く直前と行き先表示の前に `absolutePath`（包含確認）も通す。
- ホバー中のリンクの行き先は左下に「ファイルタブで開く」「ブラウザで開く」「開きません」＋URL で出す。

## HTML のレンダリング表示

| 型（`DashboardFeature/Tabs/`） | 役割 |
|---|---|
| `HTMLPreviewModel`（`HTMLPreviewView.swift`） | 文書ごとの状態。コンテンツルールの準備（`prepare`）・準備失敗（`preparationError`。失敗時は `document.presentation = .source`）・WebContent プロセス終了（`processTerminated`）・ホバー中のリンクとその行き先 |
| `HTMLContentRules` | WebKit の content rule list（識別子 `phlox-html-worktree-only-v1`）: 全 URL を block し、`^phlox-worktree://local/` だけ `ignore-previous-rules` で許可。コンパイル完了後にだけ読み込みを始める |
| `HTMLPreviewView` / `Coordinator` | `HTMLWebView`（`WKWebView` のサブクラス。右クリックメニュー無効）を作る。`allowsContentJavaScript = false`・`websiteDataStore = .nonPersistent()`・`phlox-worktree` のスキームハンドラ・`allowsLinkPreview = false`。ルールリストを設定してから `phlox-worktree://local/<パス>` を読み込む。再読込の条件は、リビジョンの変化または draft のバイト列の変化。新規ウィンドウ（`createWebViewWith`）とファイル選択パネルは拒否 |
| `HTMLLinkHover` | 専用の `WKContentWorld`（`phlox-html-link-hover`）のユーザースクリプトが、`a[href]` のマウスオーバー／フォーカスだけをメッセージ（`phloxLinkHover`）で本体へ送る。ページ側の world からは見えない |
| `WorktreeSchemeHandler` | `WKURLSchemeHandler`（`@MainActor`）。GET のみ。メイン文書（`documentPath` と同じパス）には、ディスクでなく読み込み開始時点の draft（上限 32 MiB）を返す。それ以外は `WorkingTreeService.resourceData`（包含確認・32 MiB 上限）。MIME は拡張子から `UTType`、`Cache-Control: no-store`。停止済みの task へは応答しない（task ごとの `Task` を保持し、`stop`・`stopAll` で取り消す） |
| `WorktreeURL` | `phlox-worktree://local/<パス>` の生成と解析。`%XX` を含む二重符号化・NUL・`..`・空要素・ユーザー/ポート付きを拒否 |
| `HTMLNavigationPolicy.decide`（純関数） | サブフレームは worktree 内だけ許可。メインフレームは、初回の読み込みと同一文書内のアンカー以外をキャンセルし、`linkActivated` のときだけ `linkDestination`（ファイルタブ／既定ブラウザ）。フォーム送信・ターゲットフレームなしはキャンセル |

- 帯（`FileTabView`）: HTML のレンダリング中は「外部の読み込みを止めています」（クリックで説明のポップオーバー）・「閲覧のみ」・「再読込」ボタンを出す。遮断ルールの準備に失敗するとソース表示に固定する。WebContent プロセス終了時は「表示が停止しました」と「再読込」を出し、下書きは残る。
- 再描画の契機: ソース表示からレンダリングへ戻る・「再読込」・保存成功（`htmlPreviewRevision` の増加）。draft は未保存のものが表示される。

## 未保存の確認（`FileTabDocumentRegistry`、`Tabs/FileTabDocumentRegistry.swift`）

- `FileTabDocumentRegistry.shared`（`@MainActor @Observable`）は、各ウィンドウの `FileTabDocuments`（ウィンドウごとの下書き。`DashboardView` の `@State`）を弱参照で登録する（`WindowChromeConfigurator` が `register(files:window:)` を呼ぶ）。登録時にウィンドウの delegate を `windowShouldClose` 用の `WindowDelegate` に差し替え、元の delegate へ転送する。registry と undo の差し替えは既存の連鎖に自分があれば包み直さず、再設置で循環を作らない。
- ウィンドウを閉じる: そのウィンドウの未保存（`hasUnsavedChanges`）を集め、あれば件数入りの題と一覧を持つ `NSAlert` のシートを出す。「キャンセル」が既定・最上段、「保存せず閉じる」は破壊的表示で ⌘⌫ を割り当てる。承認後に文書を失効させ、進行中の保存を待ってから閉じる。
- アプリ終了: `AppDelegate.applicationShouldTerminate` が `cleanupGuard.beginCleanup()` より前に `confirmTermination()` を呼ぶ。全ウィンドウの未保存を集め、件数入りの題と一覧を持つアラートを出す。「保存せず終了」は破壊的表示で ⌘⌫ を割り当て、キャンセルなら `.terminateCancel`。確認中の再要求は `.terminateCancel`、承認後の再要求は `.terminateLater`。承認後は `invalidateAndWait()` で全文書の保存完了を待ってから、既存の終了処理（PTY 終了・transcript flush）へ進む。
- 表示する一覧は合計 5 件まで。複数ウィンドウの場合だけウィンドウ名の見出しを付け、残りは「ほか N 件（M ウィンドウ）」、単一ウィンドウでは「ほか N 件」。未確定のブロック編集を含む文書は「編集中のブロック」のタグを付け、本文にも注意文を足す。前面順のウィンドウごとにパス順で並べる。幅は 280pt、末尾の保存案内は中央寄せ。要約も一覧と同じ可視件数・省略数モデルを使う。
- セッション削除・作業ディレクトリ変更・プロジェクト移動・子タブを閉じる確認は `dirtySummary(for:)` / `dirtyFileNames(for:)` / `hasUnsavedChanges(for:path:)` で全ウィンドウの未保存を集める。作業場所の変更中は `beginWorkspaceChange`・`beginSessionChanges` で `isChangingSession` を立てる。
- 強制終了・クラッシュ時の下書き保護は無い。

## 制約（コードで確かめた値）

| 項目 | 値・挙動 | 場所 |
|---|---|---|
| 編集できるファイルの上限 | 1,000,000 バイト | `WorkingTreeText.maximumEditableFileSize` |
| バイナリ判定 | 先頭 8,192 バイトに NUL | `WorkingTreeText.decode` |
| ブロック編集のソース固定 | 本文 500,000 バイト超、またはブロック 2,000 超、または区間の検証に失敗 | `FileTabDocument.markdownPresentationLocked`・`acceptMarkdownAnalysis` |
| ブロック編集欄の高さ | 54〜200pt | `MarkdownBlockEditor.editorHeight` |
| ツリーの 1 フォルダの表示数 | 5,000 件 | `FileTreeLoader.readDirectory` |
| HTML 配信のリソース上限 | 32 MiB（メイン文書は draft のバイト数） | `WorkingTreeService.maximumHTMLResourceSize`・`WorktreeSchemeHandler` |
| ページの JavaScript | 常に無効 | `HTMLPreviewView.Coordinator.makeWebView` |
| ページ由来の外部要求 | 全遮断（`phlox-worktree://local/` のみ許可） | `HTMLContentRules.json` |
| ブロックをまたぐ選択・コピー | できない（ブロック内のみ。ソース表示で行う） | `MarkdownBlockEditor` |
| 既知の差 | `*` と `_` を混ぜた入れ子の強調の一部は、ブロック単位の表示が文書全体の表示と異なる（ファイルの中身は変わらない） | [delivery/0038](../delivery/0038-file-explorer-and-simulator-worklog.md) の F4 記録 |

## テスト

| ファイル（`DashboardFeature/Tests`） | 固定している性質 |
|---|---|
| `WorkingTreeContainmentTests` / `WorkingTreeServiceWhiteboxTests` / `AcceptanceWorkingTreeTests` | symlink の包含確認・ルート固定・保存と競合 |
| `FileTabDocumentBytesTests` / `FileTabDocumentLifecycleTests` / `FileTabLastWriterTests` | バイト比較・BOM・失効・保存の直列化 |
| `OpenFileTabTests` / `CrossWindowDraftTests` / `TerminationConfirmationTests` | 開く共通関数・複数ウィンドウの未保存・終了確認 |
| `FileTreeLoaderTests` / `FileTreeRowsTests` / `FileTreeModelTests` / `FileTreeGitTests` | ツリーの読込・平坦化・モデル・ブランチ名 |
| `MarkdownBlocksTests` / `MarkdownRenderParityTests` / `MarkdownCorpusParityTests` / `ActiveBlockEditTests` / `MarkdownBlockEditorTests` / `MarkdownBlockEditorLifecycleTests` / `MarkdownBlockClickTests` / `MarkdownLinkRoutingTests` / `FileMarkdownPresentationTests` | ブロック分割・描画の一致・編集状態・リンク |
| `WorktreeSchemeHandlerTests` / `HTMLNavigationPolicyTests` / `HTMLContentRuleTests` / `HTMLNetworkIsolationTests` / `HTMLPreviewRefreshTests` | HTML の配信・遷移判定・遮断・再描画 |
| `FileTreeInteractionTests` / `HTMLPreviewInteractionTests` / `MarkdownBlockInteractionTests`（`macos/UITests`、XCUITest） | 実画面でのツリー操作・HTML のレンダリング・ブロック編集 |
