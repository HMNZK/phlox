---
status: active
last-verified: 2026-10-04
---

# ファイルのシンタックスハイライト

ファイルを読む・少し直すため、原文を保ったまま字句（文字の並び）に色を付ける。[ADR 0180](../adr/0180-syntax-highlighting-with-in-house-lexer.md) の採用済み方針。以下は次段の実装要件であり、現時点の動作保証ではない。

## 1. 現在の部品と不足

2026-10-04 のコードを確認した。

| 部品 | 現在の状態 |
|---|---|
| `AgentDomain/Sources/ChatRenderKit/ChatCodeTokenizer.swift` | `Rules` にキーワード・行コメント・`/* */`・引用符・三重引用符・大文字小文字の区別・名前の追加分類を保持。Swift とシェルは専用走査、ほかは共通走査。ファイル名判定・shebang・タグなどの規則は無い |
| 同部品の入口 | `path:` は拡張子で判定し未知なら plain。`language:` は未知・未指定なら Swift の簡易規則。チャットだけ型・メンバー・呼び出しを追加分類。`lineTokens` は行を連結して分類後に戻す |
| `DashboardFeature/Tabs/CodeTextEditor.swift` | TextKit 1 の `NSTextView`。生成時に `string` と段落属性を設定。更新時は UTF-8 比較で本文を同期し、本文色を設定。`Coordinator.textDidChange` が binding と行番号を更新する。色付けは無く、通常の同期には marked text の保護も無い |
| `SessionFeature/ChatComposer.swift` | `applyComposerHighlights` は `hasMarkedText()` 中は属性を変更せず、選択を復元し undo 登録を止めて属性だけを更新。binding からの本文同期も変換中は止める（経緯は [delivery 0006](../delivery/0006-ui-fixes-batch-worklog.md)） |
| パッケージの依存 | `AgentDomain/Package.swift` は `ChatRenderKit` を別 product として公開。`DashboardFeature/Package.swift` に直接の product 依存は無い。現在の `Editor/EditorPanelView.swift` は `SessionFeature.ChatCodeHighlighter` 経由で利用。直接 tokenizer を使うなら既存 AgentDomain パッケージの `ChatRenderKit` product を依存に追加する（外部依存の追加は不要） |

## 2. 種類の判定（FR-1）

判定は言語規則から独立した純関数にする。次の最初の一致を採用し、本文全体から言語を推測しない。

1. **ファイル名**: 最終要素の完全一致。`Dockerfile`・`Containerfile`、`Makefile`・`makefile`・`GNUmakefile`、`.gitignore`・`.dockerignore`・`.ignore`・`.gitattributes`、`.editorconfig`、`CMakeLists.txt`。`.env` および `.env.` で始まる名前は明示したファミリー規則（例: `.env.local`、`.env.production`）として最優先にする。ファイル名は大文字小文字を区別する。
2. **拡張子**: §3 の表。大文字小文字を区別しない。`Dockerfile.dev` / `Containerfile.dev` は `dockerfile` / `containerfile` に続く派生名としてこの段で扱う。`.h` は C/C++ の共通規則、`.m` は Objective-C、`.pl` は Perl、`.ts` は TypeScript と決める。
3. **先頭行の `#!`（shebang）**: 拡張子が未知か無い場合だけ。実行名のパス末尾を使い、`/usr/bin/env` と `env -S` の先頭の実行名も読む。`sh`/`bash`/`zsh`/`fish`、`python`/`python3`（数字の版接尾辞を含む）、`ruby`、`perl`、`php`、`lua`、`node`/`nodejs`、`pwsh`/`powershell` をそれぞれの規則へ対応させる。既に読み込み時に分離された BOM を本文へ戻さない。
4. **plain**: 未知の名前・拡張子・shebang は本文色。空ファイルも安全に扱う。

チャットのフェンス言語名は同じ規則表の別名へ対応させる。未知・未指定のフェンスを Swift として扱う現行の互換動作は今回変更しない。ファイルの plain 判定と混同しない。

## 3. 対応する種類と色付け対象（FR-2）

「簡易」は現在の規則表にあるが、右欄を満たすには補強が必要な種類。「追加」は専用規則が現在無い種類。右欄は実装後の最低範囲であり、厳密な構文解析は求めない。共通の色付け対象は各言語のキーワード・文字列・数値・コメント。文字列とコメントの内部をキーワードとして塗らない。

| 種類 | 拡張子・名前の例 | 現状 | 色付け対象・補足 |
|---|---|---|---|
| Swift | swift | 簡易 | 共通対象、`/* */`、複数行・raw 文字列を補強 |
| Objective-C / Objective-C++ | m, mm | 簡易／mm は追加 | 共通対象、`@` キーワード・文字列、プリプロセッサ命令 |
| C / C++ | c, h, cc, cpp, cxx, hpp, hh, hxx | 簡易／一部拡張子追加 | 共通対象、文字リテラル、プリプロセッサ命令 |
| Java / Kotlin / C# | java, kt, kts, cs | 簡易 | 言語別キーワード、文字・複数行文字列、注釈／属性の名前 |
| Go / Rust | go, rs | 簡易 | 共通対象、Go の raw 文字列、Rust の raw 文字列・文字リテラル。寿命名を文字列にしない |
| Python / Ruby / PHP | py, pyw, rb, php, phtml | Python・Ruby は簡易、PHP は追加 | 共通対象、Python の三重引用符、Ruby のシンボル、PHP の変数・開始終了タグ。PHP のタグ外は HTML |
| Perl / Lua / R | pl, pm, lua, r | Perl・R は簡易、Lua は追加 | 共通対象、Perl の変数、Lua の `--`・長括弧の文字列／コメント、R の言語別キーワード |
| Dart / Scala / Elixir / Haskell | dart, scala, sc, ex, exs, hs, lhs | Dart・Scala は簡易、残り追加 | 共通対象、Elixir の atom、Haskell の `--`・`{- -}`、各言語の複数行文字列。literate 記法はコード行だけ |
| JavaScript / TypeScript | js, mjs, cjs, ts, mts, cts | 簡易 | 共通対象、テンプレート文字列は全体を文字列。式の内部は解析しない |
| JSX / TSX | jsx, tsx | JS/TS と同じ簡易規則 | JS/TS に加えてタグ・属性。`{…}` 内は JS/TS の字句規則、入れ子の括弧と文字列・コメントを追跡。構文／型の解決はしない |
| シェル系 | sh, bash, zsh, fish | 簡易 | コマンド・オプション・変数・演算子・文字列・コメントに加え、制御キーワード。fish の語彙は分ける |
| PowerShell | ps1, psm1, psd1 | 追加 | キーワード・コマンド・変数・文字列・数値・`#` / `<# #>` コメント |
| SQL / GraphQL | sql, graphql, gql | SQL は簡易、GraphQL は追加 | 共通対象、SQL は大文字小文字を無視。GraphQL は操作語・変数・フィールド名・三重引用符 |
| JSON / JSONC / JSON5 | json, jsonc, json5 | 簡易 | キー・文字列・数値・真偽値・null。JSON はコメント無し、JSONC は行／ブロックコメント、JSON5 はそれに単一引用符・非引用キーを追加 |
| YAML / TOML | yaml, yml, toml | 簡易 | キー・文字列・数値・真偽値・コメント。YAML のブロック文字列、TOML の節名・日時・複数行文字列 |
| INI / cfg / conf / EditorConfig | ini, cfg, conf, .editorconfig | INI は簡易、残り追加 | 節名・キー・値・`#` / `;` コメント。cfg/conf は INI 風の汎用規則に固定し、製品固有の構文は推測しない |
| env / properties | .env 系, env, properties | 追加 | キー・代入記号・値・引用文字列・コメント。env の変数参照、properties のエスケープと継続行 |
| plist / XML / SVG | plist, xml, svg, xsd, xsl, xslt | 追加 | タグ・属性・文字列・実体参照・コメント・宣言。CDATA 内と本文は plain。plist は XML のものだけ |
| Dockerfile / Makefile / CMake | ファイル名（§2）, dockerfile, containerfile, mk, make, cmake | 簡易 | 命令／ターゲット・変数・文字列・コメント・数値。Docker の RUN と Make のレシピはシェルの字句規則 |
| gitignore 系 / gitattributes | §2 のファイル名 | 追加 | コメント、否定記号・ワイルドカード、パターン、属性名。無視される実ファイルを調べない |
| HTML | html, htm | 追加 | タグ・属性・値・実体参照・コメント。script/style 内は宣言に応じ JS/TS/JSON/CSS の規則。未知の宣言は本文色 |
| Markdown | md, markdown, mdx | 追加 | 見出し・強調／リスト等の記号・リンク先・インラインコード・HTML コメント。フェンス内は言語規則、未知／未指定は本文色。先頭 front matter は YAML。mdx の JSX はタグと属性だけ |
| CSS / SCSS / Less | css, scss, less | 追加 | セレクタ・プロパティ・値・数値／単位・文字列・コメント・at-rule、SCSS/Less の変数 |
| Vue / Svelte | vue, svelte | 追加 | HTML のタグ・属性、script/style は上記の規則（lang 属性で ts/scss/less 等）。Vue の `{{…}}`・Svelte の `{…}` は JS/TS の字句規則。テンプレート指令はキーワード。複雑な入れ子の完全解析はしない |
| CSV / TSV | csv, tsv | 追加 | 区切り記号・引用フィールド・フィールド全体が数値の値。引用内の改行・二重引用符を追跡。列の意味やヘッダーは推測しない |
| ログ | log | 追加 | 行頭の日時、独立した TRACE/DEBUG/INFO/WARN/ERROR/FATAL、数値・引用文字列。本文をコードと解釈しない |
| diff / patch | diff, patch | 追加 | 行頭の追加／削除、`---` / `+++` 等のヘッダー、`@@` の区間、注記。追加／削除本文の言語解析は行わない |
| Protobuf / Terraform・HCL / Nix | proto, tf, tfvars, hcl, nix | 追加 | 共通対象、Protobuf の型・フィールド番号、HCL のキー・ブロック名、Nix の属性名と複数行文字列 |
| LaTeX | tex, sty, cls, bib | 追加 | 命令・環境名・`%` コメント・数式の区切り・数値、BibTeX の項目型・キー・引用値 |
| plain | txt, text、判定できない種類 | 本文色 | 色を付けず原文を表示する |

種類が増えても、判定表・規則・色への割り当てを別々に保つ。規則の優先順位はコメント／文字列の境界を守り、識別子の一部分だけをキーワードにしない。未閉鎖の文字列・コメントでも停止し、分類したテキストを連結すると原文の UTF-8 と一致すること。

## 4. 色・適用先・対象外（FR-3〜5）

新しい色は追加しない。構造の種類は区別して保持し、表示時に既存色へ割り当てる。

| 対象 | 既存の色 |
|---|---|
| キーワード・命令・タグ・Markdown の構造記号・演算子・LaTeX 命令・ログレベル | `DSColor.codeSyntaxKeyword` |
| 文字列・属性値・リンク先・インラインコード・パターン・変数 | `DSColor.codeSyntaxString` |
| コメント・差分の注記 | `DSColor.codeSyntaxComment` |
| 数値・属性名・キー・節名・CSS プロパティ・日時・CSV/TSV 区切り・オプション | `DSColor.codeSyntaxNumber` |
| diff の追加行／削除行 | 既存の `DSColor.diffAdded` / `DSColor.diffRemoved`（追加・削除の意味と既存の変更表示に合わせる） |
| diff のヘッダー／区間 | `DSColor.codeSyntaxComment` / `DSColor.codeSyntaxKeyword`。`---` / `+++` は追加・削除より先に判定 |
| 通常の本文 | ファイルは `DSColor.textPrimary`、チャットは従来の `DSColor.chatTextPrimary` |

ファイル入力欄は前景色だけを変える。チャットの既存の型・呼び出し・メンバー等の色とキーワードの太字、変更タブの名前を細分しない見せ方は維持する。

- **FR-3**: ファイルタブのソース表示に適用する。`.md` / `.html` のソース表示も含め、レンダリング表示は変えない。
- **FR-4**: Markdown のブロック編集欄にも適用する。同じ `CodeTextEditor` で原文を編集するため。通常ブロックは Markdown、front matter は YAML。フェンスはブロック全体から開始状態を読み、内部のコードに対応する規則を使う。文書上の位置は維持する。
- **FR-5**: チャットのフェンスと変更タブは同じ部品の規則拡張で対応範囲が広がる。ファイル名優先の判定も変更タブへ共有し、既存の行数・複数行の状態・差分表示を保つ。

色付けをしない対象は以下。未知のテキストを開けなくする理由にはしない。

| 対象 | 扱い・理由 |
|---|---|
| バイナリ・UTF-8 でないファイル・1,000,000 バイト超 | 既存の読込制限を維持。バイナリ plist も対象外。色付けのために復号や上限を変えない |
| 巨大な minified 相当の行 | 1 行が改行を除き UTF-16 で 10,000 単位を超える文書は色付けせず本文色で編集可能にする。長い単一行の属性・レイアウト負荷を避ける。圧縮形式を拡張子だけで決めない |
| 未知の言語、設定製品ごとの方言、上表外の形式 | plain に戻す。すべてのテキストを表示できることと、すべての言語を厳密に解析することは分ける |
| 正規表現と割り算、埋め込み式、ヒアドキュメント等 | ADR 0180 の限界。字句で分かる範囲だけを色付けし、誤判定でも入力・保存を妨げない |

## 5. 編集を守る条件（NFR）

| ID | 要件・受け入れ基準 |
|---|---|
| NFR-1 入力速度 | 上限 1,000,000 バイトまで、入力処理と色付け属性適用がメインスレッドを長く占有しない。初回は全文を背景計算。編集時も全文の再計算を背景で行い、50 ms の待機で連続入力をまとめる。変更行だけの字句再計算は初版では採らない（複数行コメント・文字列の状態が後続へ波及するため）。古い計算は取り消し／破棄し、最新の本文・種類に一致する結果だけを使う。属性は変わった範囲へ適用し、必要なら処理を分ける |
| NFR-2 日本語入力 | `hasMarkedText()` 中は本文の再設定・色付け属性の更新を行わない。計算済みの結果も保留し、確定後に現在の本文で再計算する。色付け処理が `unmarkText()` を呼ばない。既存の明示的なブロック編集確定とは分ける |
| NFR-3 undo | 色付けの属性操作を undo に登録しない。入力・削除・貼り付け・ブロック確定の履歴とまとまりを保つ |
| NFR-4 選択・カーソル | 全選択範囲・挿入位置・スクロール位置を保持。UTF-16 の範囲で属性を付け、絵文字・結合文字・CRLF でずれない。typingAttributes に直前のトークン色を残さない |
| NFR-5 テーマ | ライト／ダークの切替で現在の DSColor を解決し直す。色を含むキャッシュにはテーマを含める。変換中の切替も NFR-2 を優先し、確定後に追従する |
| NFR-6 原文・保存 | 色付けは表示属性だけ。draft・文書 version・dirty・保存バイト列を変えない。BOM・LF/CRLF/CR・末尾改行・Unicode の表現を保持。属性更新を本文変更通知として再処理しない |

**NFR-1 の測定**: 実装時に使用 Mac・OS・ビルド構成を記録し、10 KB / 100 KB / 1,000,000 バイトの Swift・JSON・Markdown・多言語混在の本文を用意する。上限側には細かいトークンが多い例と複数行文字列を含め、色付けが動く長さの行で測る。各例はウォームアップ後、先頭・中央・末尾で挿入／削除／貼り付けを計 100 回行う。`ContinuousClock` 等でイベント処理開始から本文反映までと、最終入力から色の適用完了までを別に測る。入力処理と 1 回の属性適用はそれぞれ p95 ≤ 16 ms、入力を止めた後の色付け完了は p95 ≤ 150 ms を受け入れ基準にする。上限超過・長行の plain 化も別に確認する。これらの値は目標であり未測定。未達なら実装を改善し、測定無しで達成扱いにしない。

## 6. テスト方針

次段で追加する検査であり、今のテストに入っているという主張ではない。

| 層 | 検査すること |
|---|---|
| 字句の単体テスト（AgentDomain / ChatRenderKit） | §3 の各種類の代表例と反例、別名、ファイル名→拡張子→shebang→plain の競合、空・未閉鎖・長行境界、Unicode・改行、コメント／文字列内部の抑制、連結した原文のバイト一致、複数行の状態、埋め込み領域の切替 |
| 入力欄の単体・統合テスト（DashboardFeature） | 生成・binding 更新・編集通知・種類変更・テーマ変更、古い結果の破棄、marked text の保留と確定、undo/redo、選択・スクロール・typingAttributes、保存前後のバイト一致と dirty 不変、Markdown ブロック編集と確定 |
| 共有部品の回帰（SessionFeature） | フェンス言語の対応拡張、未知言語の現行互換、チャット固有の名前分類・太字、変更タブの既存表示。既存テストをスキップ／弱化しない |
| 性能 | §5 のデータ・計測条件で入力時間と色付け時間を分けて記録。背景計算の取消と、初回・テーマ切替でメインスレッドを占有しないことも確認 |
| 見た目 | `NSHostingView.cacheDisplay` 等の画面外描画でライト／ダークを撮り、`specs/ClaudeDesign/` のソース／ブロック編集の見本（4j・4m 等）と行番号・行間・余白・選択を比較。字句の色は §4 と既存のコード表示を基準にする。見本のプレーン表示や太字を新仕様へ無条件に持ち込まない |

触ったパッケージは `~/.agents/scripts/compact-test <ラベル> swift test --package-path <パッケージ>` で全数を実行する。コード変更時のプロジェクト品質ゲートは、その worktree の設定を確認して実行する。画面外描画で本物の IME 操作まで検証したとは扱わない。必要な XCUITest は実装時に一覧を作り、`-derivedDataPath` を worktree 内にした `xcodebuild build-for-testing` のみ実行する。PM 向けに実在する `-only-testing:` 指定を報告し、ユーザーの画面を操作するテストは実行しない。
